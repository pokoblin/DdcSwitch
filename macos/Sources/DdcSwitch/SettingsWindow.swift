// The settings window: a classic macOS preferences window with toolbar panes, each pane a
// SwiftUI grouped form. The window title follows the selected pane and the window resizes to fit it.

import AppKit
import Combine
import SwiftUI

final class SettingsWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private let model: SettingsModel
    private let hosting: NSHostingController<SettingsRoot>
    private var observers: Set<AnyCancellable> = []

    init(model: SettingsModel) {
        self.model = model
        hosting = NSHostingController(rootView: SettingsRoot(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        // Appear at once, without the zoom-in animation of document windows.
        window.animationBehavior = .none
        window.setFrameAutosaveName("DdcSwitchSettings")
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "DdcSwitchSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        model.$pane.combineLatest(model.$strings).receive(on: RunLoop.main).sink { [weak self] pane, strings in
            self?.update(pane: pane, strings: strings)
        }.store(in: &observers)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            // Size the window to the pane before it appears, so it doesn't open small and then grow.
            hosting.view.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.view.fittingSize)
            window.center()
        }
        // A menu bar app is never the active app, and since macOS 14 a plain NSApp.activate() is only
        // a request the active app may ignore, which leaves the window behind it. Force it to the front.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func update(pane: SettingsModel.Pane, strings: Strings) {
        window?.title = pane.title(strings)
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(pane.rawValue)
        for item in window?.toolbar?.items ?? [] {
            if let p = SettingsModel.Pane(rawValue: item.itemIdentifier.rawValue) { item.label = p.title(strings) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.recording = nil
    }

    // Toolbar

    private var identifiers: [NSToolbarItem.Identifier] { SettingsModel.Pane.allCases.map { .init($0.rawValue) } }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsModel.Pane(rawValue: id.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = pane.title(model.strings)
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil)
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = SettingsModel.Pane(rawValue: sender.itemIdentifier.rawValue) else { return }
        model.recording = nil
        model.pane = pane
    }
}

// ---------------------------------------------------------------------------

struct SettingsRoot: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Group {
            switch model.pane {
            case .general: GeneralPane(model: model)
            case .monitor: MonitorPane(model: model)
            case .shortcuts: ShortcutsPane(model: model)
            case .power: PowerPane(model: model)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollDisabled(true)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Explanation under a group, aligned with the group's labels like in System Settings.
struct Footnote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A warning shown next to the setting it belongs to.
struct Issue: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.multicolor)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let t = model.strings
        Form {
            Section {
                Toggle(t.launchAtLogin, isOn: $model.launchAtLogin)
                if model.loginNeedsApproval {
                    LabeledContent {
                        Button(t.openLoginItems) { LaunchAtLogin.openSystemSettings() }
                    } label: {
                        Issue(text: t.loginNeedsApproval)
                    }
                }
                if let error = model.loginError { Issue(text: error) }
            } footer: {
                Footnote(text: t.launchAtLoginFooter)
            }

            Section {
                Toggle(t.notifySuccess, isOn: $model.notifySuccess)
            } footer: {
                Footnote(text: t.notifyFooter)
            }

            Section {
                Picker(t.appearance, selection: $model.appearance) {
                    Text(t.appearanceAuto).tag("auto")
                    Divider()
                    Text(t.appearanceLight).tag("light")
                    Text(t.appearanceDark).tag("dark")
                }
                Picker(t.language, selection: $model.language) {
                    Text(t.langAuto).tag("auto")
                    Divider()
                    ForEach(I18n.languages, id: \.code) { lang in
                        Text(lang.strings.langName).tag(lang.code)
                    }
                }
            }

            Section {
                LabeledContent(t.log) {
                    Button(t.openLog) { NSApp.sendAction(#selector(AppController.openLog), to: nil, from: nil) }
                }
                LabeledContent(t.configFile) {
                    Button(t.showInFinder) { NSWorkspace.shared.activateFileViewerSelecting([Paths.configFile]) }
                }
                if let error = model.saveError { Issue(text: error) }
            } footer: {
                HStack(spacing: 6) {
                    Text(I18n.fmt(t.version, AppIdentity.version)).foregroundStyle(.tertiary)
                    Text("·").foregroundStyle(.tertiary)
                    Link("GitHub", destination: AppIdentity.repository)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

struct MonitorPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let t = model.strings
        Form {
            Section {
                if model.monitorNames.isEmpty {
                    LabeledContent(t.monitor) { Text(t.noMonitors).foregroundStyle(.secondary) }
                } else {
                    Picker(t.monitor, selection: $model.monitorSelection) {
                        ForEach(Array(model.monitorNames.enumerated()), id: \.offset) { i, name in
                            Text("\(i + 1): \(name)").tag(i)
                        }
                    }
                }
                LabeledContent(t.currentInput) {
                    switch model.probeState {
                    case .idle:
                        Text("—").foregroundStyle(.secondary)
                    case .reading:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(t.reading).foregroundStyle(.secondary)
                        }
                    case .done(let current, let failed, _):
                        if failed {
                            Issue(text: current).multilineTextAlignment(.trailing)
                        } else {
                            Text(current).textSelection(.enabled)
                        }
                    }
                }
                LabeledContent(t.reportedInputs) {
                    switch model.probeState {
                    case .done(_, _, let inputs) where !inputs.isEmpty:
                        Text(inputs.map(inputLabel).joined(separator: "\n"))
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    case .done:
                        Text(t.notReported).foregroundStyle(.secondary)
                    default:
                        Text("—").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 10) {
                    Footnote(text: t.monitorFooter)
                    HStack {
                        Spacer()
                        Button(t.detectAgain) { model.redetect() }
                            .disabled(model.probeState == .reading)
                    }
                }
            }
        }
    }
}

struct ShortcutsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let t = model.strings
        Form {
            ForEach(model.rows.indices, id: \.self) { i in
                Section {
                    Toggle(t.enabled, isOn: $model.rows[i].enabled)
                    Group {
                        TextField(t.name, text: $model.rows[i].name, prompt: Text(t.namePrompt))
                        LabeledContent(t.targetInput) {
                            InputComboBox(text: $model.rows[i].inputText, items: model.inputChoices)
                                .frame(width: 180)
                        }
                        LabeledContent(t.shortcut) {
                            ShortcutRecorder(model: model, row: i)
                        }
                    }
                    .disabled(!model.rows[i].enabled)
                    if model.rows[i].enabled, let issue = model.rowIssues[safe: i] ?? nil {
                        Issue(text: issue)
                    }
                } header: {
                    Text(I18n.fmt(t.shortcutRow, i + 1))
                } footer: {
                    if i == model.rows.count - 1 {
                        Footnote(text: t.shortcutsFooter)
                    }
                }
            }
        }
    }
}

struct PowerPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let t = model.strings
        Form {
            Section {
                LabeledContent(t.switchTo) {
                    InputComboBox(text: $model.shutdownInputText, items: model.inputChoices)
                        .frame(width: 180)
                }
                if let issue = model.shutdownIssue { Issue(text: issue) }
            }
            Section {
                Toggle(t.beforeShutdown, isOn: $model.shutdownSwitch)
                Toggle(t.skipOnRestart, isOn: $model.skipOnRestart)
                    .disabled(!model.shutdownSwitch)
                    .padding(.leading, 16)
                Toggle(t.beforeSleep, isOn: $model.sleepSwitch)
            } footer: {
                Footnote(text: t.powerFooter)
            }
            if !model.launchAtLogin && (model.shutdownSwitch || model.sleepSwitch) {
                Section {
                    LabeledContent {
                        Button(t.turnOnLaunchAtLogin) { model.launchAtLogin = true }
                    } label: {
                        Issue(text: t.notRunningAtLogin)
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------

/// An editable NSComboBox: pick a reported input or type any code.
struct InputComboBox: NSViewRepresentable {
    @Binding var text: String
    let items: [String]
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.usesDataSource = false
        box.completes = false
        box.numberOfVisibleItems = 10
        box.delegate = context.coordinator
        box.controlSize = .regular
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if box.objectValues as? [String] != items {
            box.removeAllItems()
            box.addItems(withObjectValues: items)
        }
        if box.stringValue != text && box.currentEditor() == nil { box.stringValue = text }
        box.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: InputComboBox
        init(_ parent: InputComboBox) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let box = note.object as? NSComboBox else { return }
            parent.text = box.stringValue
        }

        func comboBoxSelectionDidChange(_ note: Notification) {
            guard let box = note.object as? NSComboBox, box.indexOfSelectedItem >= 0,
                  let value = box.itemObjectValue(at: box.indexOfSelectedItem) as? String else { return }
            parent.text = value
        }
    }
}

/// Click, then press a key combination. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    @ObservedObject var model: SettingsModel
    let row: Int
    @State private var monitor: Any?
    @State private var liveMods: Modifiers = []
    @Environment(\.isEnabled) private var isEnabled

    private var recording: Bool { model.recording == row }
    private var binding: SettingsModel.Row { model.rows[row] }

    var body: some View {
        let t = model.strings
        HStack(spacing: 4) {
            Button(action: toggle) {
                Text(label(t))
                    .foregroundStyle(recording || binding.key == nil ? .secondary : .primary)
                    .frame(minWidth: 132)
            }
            .buttonStyle(RecorderStyle(recording: recording))
            .help(t.recordShortcut)
            if binding.key != nil && !recording {
                Button {
                    model.rows[row].key = nil
                    model.rows[row].mods = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help(t.clearShortcut)
                .accessibilityLabel(t.clearShortcut)
            }
        }
        .onChange(of: model.recording) { value in
            if value != row { stopMonitor() }
        }
        .onDisappear {
            if recording { model.recording = nil }
            stopMonitor()
        }
    }

    private func label(_ t: Strings) -> String {
        if recording { return liveMods.isEmpty ? t.typeShortcut : liveMods.symbols + "…" }
        return binding.key == nil ? t.recordShortcut : hotkeyDisplay(binding.mods, binding.key)
    }

    private func toggle() {
        if recording {
            model.recording = nil
            return
        }
        model.recording = row
        liveMods = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let mods = Modifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        if event.type == .flagsChanged {
            liveMods = mods
            return nil
        }
        let code = event.keyCode
        if mods.isEmpty && Int(code) == kVKEscape {
            model.recording = nil
            return nil
        }
        if mods.isEmpty && (Int(code) == kVKDelete || Int(code) == kVKForwardDelete) {
            model.rows[row].key = nil
            model.rows[row].mods = []
            model.recording = nil
            return nil
        }
        if mods.isEmpty && !KeyCode.isFunctionKey(code) {
            NSSound.beep() // a shortcut needs ⌃, ⌥, ⇧ or ⌘ (function keys excepted)
            return nil
        }
        model.rows[row].mods = mods
        model.rows[row].key = code
        model.recording = nil
        return nil
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        liveMods = []
    }
}

private let kVKEscape = 0x35
private let kVKDelete = 0x33
private let kVKForwardDelete = 0x75

/// Looks like a text field; the border turns into the focus ring while recording.
struct RecorderStyle: ButtonStyle {
    let recording: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(recording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: recording ? 2 : 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .contentShape(Rectangle())
    }
}
