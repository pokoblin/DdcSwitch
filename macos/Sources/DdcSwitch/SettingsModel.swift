// State behind the settings window. As usual on macOS, every change takes effect immediately:
// there is no OK button. Problems are shown next to the setting they belong to.

import AppKit
import Combine

final class SettingsModel: ObservableObject {
    enum Pane: String, CaseIterable {
        case general, monitor, shortcuts, power

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .monitor: return "display"
            case .shortcuts: return "keyboard"
            case .power: return "power"
            }
        }

        func title(_ t: Strings) -> String {
            switch self {
            case .general: return t.paneGeneral
            case .monitor: return t.paneMonitor
            case .shortcuts: return t.paneShortcuts
            case .power: return t.panePower
            }
        }
    }

    struct Row: Equatable {
        var enabled: Bool
        var name: String
        var inputText: String
        var mods: Modifiers
        var key: UInt16?
    }

    enum Probe: Equatable {
        case idle
        case reading
        case done(current: String, failed: Bool, inputs: [UInt32])
    }

    private unowned let app: AppController
    private var loading = false
    private var probeSeq = 0

    @Published var pane: Pane = .general
    @Published private(set) var strings: Strings = I18n.t

    @Published private(set) var monitorNames: [String] = []
    @Published var monitorSelection = 0 {
        didSet { if !loading && monitorSelection != oldValue { commit(); probe() } }
    }
    @Published private(set) var probeState: Probe = .idle

    @Published var rows: [Row] = [] { didSet { commit() } }
    @Published private(set) var rowIssues: [String?] = Array(repeating: nil, count: hotkeySlots)
    /// Row whose shortcut is being recorded; the registered shortcuts are paused meanwhile.
    @Published var recording: Int? {
        didSet { if recording != oldValue { app.setHotkeysSuspended(recording != nil); if recording == nil { commit() } } }
    }

    @Published var shutdownInputText = "" { didSet { commit() } }
    @Published var shutdownSwitch = true { didSet { commit() } }
    @Published var skipOnRestart = true { didSet { commit() } }
    @Published var sleepSwitch = false { didSet { commit() } }
    @Published private(set) var shutdownIssue: String?

    @Published var notifySuccess = false { didSet { commit() } }
    @Published var language = "auto" { didSet { if language != oldValue { commit() } } }
    @Published var appearance = "auto" { didSet { if appearance != oldValue { commit() } } }
    @Published var launchAtLogin = false { didSet { if !loading && launchAtLogin != oldValue { setLaunchAtLogin(launchAtLogin) } } }
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var loginError: String?
    @Published private(set) var saveError: String?

    init(app: AppController) {
        self.app = app
    }

    /// Choices offered in the input combo boxes: what the monitor reports, otherwise the standard ones.
    var inputChoices: [String] {
        if case .done(_, _, let inputs) = probeState, !inputs.isEmpty { return inputs.map(inputLabel) }
        return standardInputs.map(inputLabel)
    }

    // -----------------------------------------------------------------------

    func reload(from cfg: Config) {
        loading = true
        defer { loading = false }
        strings = I18n.t
        rows = cfg.bindings.map { Row(enabled: $0.enabled, name: $0.name, inputText: inputLabel($0.input), mods: $0.mods, key: $0.key) }
        shutdownSwitch = cfg.shutdownSwitch
        shutdownInputText = inputLabel(cfg.shutdownInput)
        skipOnRestart = cfg.skipOnRestart
        sleepSwitch = cfg.sleepSwitch
        notifySuccess = cfg.notifySuccess
        appearance = cfg.appearance
        language = I18n.languages.first { $0.code.caseInsensitiveCompare(cfg.language) == .orderedSame }?.code ?? "auto"
        refreshLaunchAtLogin()
        validate(cfg)
        if monitorNames.isEmpty { redetect() }
    }

    func refreshLaunchAtLogin() {
        let was = loading
        loading = true
        launchAtLogin = LaunchAtLogin.isEnabled
        loginNeedsApproval = LaunchAtLogin.needsApproval
        loading = was
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            loginError = nil
        } catch {
            loginError = I18n.fmt(strings.launchAtLoginFailed, error.localizedDescription)
        }
        refreshLaunchAtLogin()
    }

    /// Re-enumerates the monitors (off the main thread: DDC/CI may be busy with a probe).
    func redetect() {
        let cfg = app.cfg
        DispatchQueue.global(qos: .userInitiated).async {
            let names = DDC.listNames()
            DispatchQueue.main.async {
                let previous = self.monitorNames[safe: self.monitorSelection]
                let wanted = previous ?? cfg.monitorName
                self.loading = true
                self.monitorNames = names
                self.monitorSelection = names.firstIndex(of: wanted) ?? min(max(cfg.monitor - 1, 0), max(names.count - 1, 0))
                self.loading = false
                self.probe()
            }
        }
    }

    /// Reads the current input and the supported inputs (the capabilities request takes a second or two).
    func probe() {
        probeSeq += 1
        let seq = probeSeq
        guard let name = monitorNames[safe: monitorSelection] else {
            probeState = .idle
            return
        }
        probeState = .reading
        let index = monitorSelection + 1
        DispatchQueue.global(qos: .userInitiated).async {
            var current: String
            var failed = false
            do {
                current = inputLabel(try DDC.getInput(index: index, name: name))
            } catch {
                current = "\(error)"
                failed = true
            }
            let inputs = (try? DDC.capabilities(index: index, name: name)).map(DDC.parseInputCaps) ?? []
            DispatchQueue.main.async {
                guard seq == self.probeSeq else { return }
                self.probeState = .done(current: current, failed: failed, inputs: inputs)
            }
        }
    }

    // -----------------------------------------------------------------------

    /// Builds the config from the controls and hands it to the app.
    private func commit() {
        guard !loading, !rows.isEmpty else { return }
        var cfg = app.cfg
        if let name = monitorNames[safe: monitorSelection] {
            cfg.monitor = monitorSelection + 1
            cfg.monitorName = name
        }
        for (i, row) in rows.enumerated() where i < cfg.bindings.count {
            cfg.bindings[i] = HotkeyBinding(
                enabled: row.enabled,
                name: row.name.trimmingCharacters(in: .whitespaces),
                input: parseInput(row.inputText) ?? cfg.bindings[i].input,
                mods: row.key == nil ? [] : row.mods,
                key: row.key
            )
        }
        cfg.shutdownSwitch = shutdownSwitch
        cfg.shutdownInput = parseInput(shutdownInputText) ?? cfg.shutdownInput
        cfg.skipOnRestart = skipOnRestart
        cfg.sleepSwitch = sleepSwitch
        cfg.notifySuccess = notifySuccess
        cfg.language = language
        cfg.appearance = appearance

        let languageChanged = cfg.language != app.cfg.language
        saveError = app.apply(cfg, invalidRows: validate(cfg))
        if languageChanged { strings = I18n.t }
        validate(cfg)
    }

    /// Fills in the problems shown under the rows; returns the rows that must not be registered.
    @discardableResult
    private func validate(_ cfg: Config) -> Set<Int> {
        let t = I18n.t
        var invalid = Set<Int>()
        var issues = [String?](repeating: nil, count: rows.count)
        var used: [(Modifiers, UInt16)] = []
        for (i, row) in rows.enumerated() where row.enabled {
            let issue: String?
            if parseInput(row.inputText) == nil {
                issue = I18n.fmt(t.errRowInput, row.inputText)
            } else if row.key == nil {
                issue = t.errRowNoHotkey
            } else if row.mods.isEmpty && !KeyCode.isFunctionKey(row.key!) {
                issue = t.errRowModifier
            } else if used.contains(where: { $0.0 == row.mods && $0.1 == row.key! }) {
                issue = I18n.fmt(t.errRowDuplicate, hotkeyDisplay(row.mods, row.key))
            } else {
                issue = nil
                used.append((row.mods, row.key!))
            }
            if let issue {
                issues[i] = issue
                invalid.insert(i)
            }
        }
        // Shortcuts that passed the checks but are owned by another app.
        for i in app.hotkeyFailures where issues[safe: i] == .some(nil) && !invalid.contains(i) {
            issues[i] = I18n.fmt(t.hotkeyInUse, hotkeyDisplay(cfg.bindings[i].mods, cfg.bindings[i].key))
        }
        rowIssues = issues
        let needsInput = shutdownSwitch || sleepSwitch
        shutdownIssue = needsInput && parseInput(shutdownInputText) == nil ? I18n.fmt(t.errShutdownInput, shutdownInputText) : nil
        return invalid
    }
}
