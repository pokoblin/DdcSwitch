// Settings persisted as a small `key = value` file in ~/Library/Application Support/DdcSwitch.
// Same keys as the Windows version's config.ini; hotkeys use macOS modifiers (Ctrl, Opt, Shift, Cmd).

import Foundation

let hotkeySlots = 3

/// VCP code for "Input Select".
let vcpInput: UInt8 = 0x60

struct HotkeyBinding: Equatable {
    var enabled: Bool
    var name: String
    var input: UInt32
    var mods: Modifiers
    /// macOS virtual key code (kVK_*), nil when no shortcut is set.
    var key: UInt16?
}

struct Config: Equatable {
    /// 1-based monitor number, as listed by `--list`.
    var monitor = 1
    /// Preferred over `monitor` when a monitor with this name is present.
    var monitorName = ""
    var bindings: [HotkeyBinding] = [
        HotkeyBinding(enabled: true, name: "Windows (HDMI-1)", input: 17, mods: [.control, .option, .command], key: KeyCode.left),
        HotkeyBinding(enabled: false, name: "MacBook (USB-C)", input: 25, mods: [.control, .option, .command], key: KeyCode.right),
        HotkeyBinding(enabled: false, name: "", input: 15, mods: [], key: nil),
    ]
    var shutdownSwitch = true
    var shutdownInput: UInt32 = 17
    var skipOnRestart = true
    var sleepSwitch = false
    var notifySuccess = false
    /// "auto" or a language code from `I18n.languages`.
    var language = "auto"
    /// "auto" (follow the system), "light" or "dark". macOS only; Windows ignores the key.
    var appearance = "auto"

    /// Loads the config file; `existed` is false when no file existed yet.
    static func load(from url: URL = Paths.configFile) -> (config: Config, existed: Bool) {
        var cfg = Config()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return (cfg, false) }
        cfg.parse(text)
        return (cfg, true)
    }

    mutating func parse(_ text: String) {
        // Files edited on Windows may carry a BOM and CRLF line endings.
        let body = text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            apply(key: key, value: value)
        }
    }

    private mutating func apply(key: String, value: String) {
        let flag = ["1", "true", "yes", "on"].contains(value.lowercased())
        switch key {
        case "monitor": monitor = max(Int(value) ?? 1, 1)
        case "monitor_name": monitorName = value
        case "shutdown_switch": shutdownSwitch = flag
        case "shutdown_input": shutdownInput = parseInput(value) ?? shutdownInput
        case "skip_on_restart": skipOnRestart = flag
        case "sleep_switch": sleepSwitch = flag
        case "notify_success": notifySuccess = flag
        case "language": language = value
        case "appearance": appearance = ["light", "dark"].contains(value.lowercased()) ? value.lowercased() : "auto"
        default:
            // hotkeyN, hotkeyN_enabled, hotkeyN_name, hotkeyN_input
            guard key.hasPrefix("hotkey") else { return }
            let rest = key.dropFirst("hotkey".count)
            let parts = rest.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
            guard let n = Int(parts[0]), (1...bindings.count).contains(n) else { return }
            let field = parts.count > 1 ? String(parts[1]) : ""
            switch field {
            case "":
                let (mods, key) = parseHotkey(value) ?? ([], nil)
                bindings[n - 1].mods = mods
                bindings[n - 1].key = key
            case "enabled": bindings[n - 1].enabled = flag
            case "name": bindings[n - 1].name = value
            case "input": bindings[n - 1].input = parseInput(value) ?? bindings[n - 1].input
            default: break
            }
        }
    }

    func serialized() -> String {
        var s = "# DdcSwitch settings (also editable from the menu bar icon -> Settings)\n"
        s += "language = \(language)\n"
        s += "appearance = \(appearance)\n"
        s += "monitor = \(monitor)\nmonitor_name = \(monitorName)\n\n"
        for (i, b) in bindings.enumerated() {
            let n = i + 1
            s += "hotkey\(n) = \(hotkeyToString(b.mods, b.key))\n"
            s += "hotkey\(n)_enabled = \(b.enabled)\n"
            s += "hotkey\(n)_name = \(b.name)\n"
            s += "hotkey\(n)_input = \(b.input)\n\n"
        }
        s += "shutdown_switch = \(shutdownSwitch)\n"
        s += "shutdown_input = \(shutdownInput)\n"
        s += "skip_on_restart = \(skipOnRestart)\n"
        s += "sleep_switch = \(sleepSwitch)\n"
        s += "notify_success = \(notifySuccess)\n"
        return s
    }

    func save(to url: URL = Paths.configFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try serialized().write(to: url, atomically: true, encoding: .utf8)
    }

    /// "Windows (HDMI-1) [17]" style title for an input value, using a binding name if one targets it.
    func inputTitle(_ input: UInt32) -> String {
        if let b = bindings.first(where: { $0.input == input && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "\(b.name.trimmingCharacters(in: .whitespaces)) [\(input)]"
        }
        return inputLabel(input)
    }
}

enum Paths {
    private(set) static var configFile: URL = defaultConfigFile

    static var defaultConfigFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DdcSwitch/config.ini")
    }

    static var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DdcSwitch/DdcSwitch.log")
    }

    static func setConfigFile(_ url: URL?) {
        configFile = url ?? defaultConfigFile
    }
}

// ---------------------------------------------------------------------------
// Input source names (MCCS VCP 0x60 values)

func inputName(_ v: UInt32) -> String? {
    switch v {
    case 1: return "VGA-1"
    case 2: return "VGA-2"
    case 3: return "DVI-1"
    case 4: return "DVI-2"
    case 5: return "Composite-1"
    case 6: return "Composite-2"
    case 7: return "S-Video-1"
    case 8: return "S-Video-2"
    case 12: return "Component-1"
    case 13: return "Component-2"
    case 15: return "DP-1"
    case 16: return "DP-2"
    case 17: return "HDMI-1"
    case 18: return "HDMI-2"
    case 27: return "USB-C"
    default: return nil
    }
}

func inputLabel(_ v: UInt32) -> String {
    if let n = inputName(v) { return "\(v) - \(n)" }
    return "\(v) (0x\(String(format: "%02X", v)))"
}

/// Accepts "25", "0x19", "25 - USB-C", or ddcctl-style aliases like "hdmi1".
func parseInput(_ s: String) -> UInt32? {
    let token = String(s.trimmingCharacters(in: .whitespaces).prefix { $0.isASCII && ($0.isLetter || $0.isNumber) })
    let lower = token.lowercased()
    let value: UInt32?
    if lower.hasPrefix("0x") {
        value = UInt32(lower.dropFirst(2), radix: 16)
    } else if !lower.isEmpty && lower.allSatisfy(\.isNumber) {
        value = UInt32(lower)
    } else {
        let aliases: [String: UInt32] = [
            "vga1": 1, "dvi1": 3, "dvi2": 4, "composite": 8, "svideo": 9,
            "dp1": 15, "dp2": 16, "hdmi1": 17, "hdmi2": 18, "usbc": 27,
        ]
        value = aliases[lower]
    }
    guard let v = value, (1...0xFFFF).contains(v) else { return nil }
    return v
}

/// Offered in the input pickers until the monitor reports its own list.
let standardInputs: [UInt32] = [15, 16, 17, 18, 27]
