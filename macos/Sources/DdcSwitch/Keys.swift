// Keyboard shortcuts: modifiers, macOS virtual key codes and their names.
// Config text looks like "Ctrl+Opt+Cmd+Right"; the UI shows "⌃⌥⌘→".

import AppKit
import Carbon.HIToolbox

struct Modifiers: OptionSet, Hashable {
    let rawValue: UInt32
    static let control = Modifiers(rawValue: 1 << 0)
    static let option = Modifiers(rawValue: 1 << 1)
    static let shift = Modifiers(rawValue: 1 << 2)
    static let command = Modifiers(rawValue: 1 << 3)

    /// Apple's order: ⌃ ⌥ ⇧ ⌘.
    static let ordered: [(Modifiers, config: String, symbol: String)] = [
        (.control, "Ctrl", "⌃"), (.option, "Opt", "⌥"), (.shift, "Shift", "⇧"), (.command, "Cmd", "⌘"),
    ]

    init(rawValue: UInt32) { self.rawValue = rawValue }

    init(_ flags: NSEvent.ModifierFlags) {
        var m: Modifiers = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        self = m
    }

    var eventFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if contains(.control) { f.insert(.control) }
        if contains(.option) { f.insert(.option) }
        if contains(.shift) { f.insert(.shift) }
        if contains(.command) { f.insert(.command) }
        return f
    }

    var carbonFlags: UInt32 {
        var f = 0
        if contains(.control) { f |= controlKey }
        if contains(.option) { f |= optionKey }
        if contains(.shift) { f |= shiftKey }
        if contains(.command) { f |= cmdKey }
        return UInt32(f)
    }

    var symbols: String { Modifiers.ordered.filter { contains($0.0) }.map(\.symbol).joined() }
}

enum KeyCode {
    static let left = UInt16(kVK_LeftArrow)
    static let right = UInt16(kVK_RightArrow)

    struct Info {
        let code: Int
        /// Name used in config.ini (Windows-compatible where a Windows name exists).
        let name: String
        /// Shown in the UI.
        let symbol: String
        /// NSMenuItem key equivalent.
        let equivalent: String
    }

    private static func fn(_ c: Int) -> String { String(Character(UnicodeScalar(UInt32(c))!)) }

    static let table: [Info] = {
        var t: [Info] = []
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"), (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"),
            (kVK_ANSI_9, "9"), (kVK_ANSI_Equal, "="), (kVK_ANSI_Minus, "-"), (kVK_ANSI_LeftBracket, "["),
            (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Quote, "'"), (kVK_ANSI_Semicolon, ";"),
            (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Comma, ","), (kVK_ANSI_Slash, "/"), (kVK_ANSI_Period, "."),
            (kVK_ANSI_Grave, "`"),
        ]
        for (c, n) in letters { t.append(Info(code: c, name: n, symbol: n, equivalent: n.lowercased())) }

        let fkeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (i, c) in fkeys.enumerated() {
            t.append(Info(code: c, name: "F\(i + 1)", symbol: "F\(i + 1)", equivalent: fn(NSF1FunctionKey + i)))
        }

        let named: [(Int, String, String, String)] = [
            (kVK_LeftArrow, "Left", "←", fn(NSLeftArrowFunctionKey)),
            (kVK_RightArrow, "Right", "→", fn(NSRightArrowFunctionKey)),
            (kVK_UpArrow, "Up", "↑", fn(NSUpArrowFunctionKey)),
            (kVK_DownArrow, "Down", "↓", fn(NSDownArrowFunctionKey)),
            (kVK_Home, "Home", "↖", fn(NSHomeFunctionKey)),
            (kVK_End, "End", "↘", fn(NSEndFunctionKey)),
            (kVK_PageUp, "PageUp", "⇞", fn(NSPageUpFunctionKey)),
            (kVK_PageDown, "PageDown", "⇟", fn(NSPageDownFunctionKey)),
            (kVK_Space, "Space", "Space", " "),
            (kVK_Return, "Enter", "↩", "\r"),
            (kVK_Tab, "Tab", "⇥", "\t"),
            (kVK_Escape, "Esc", "⎋", "\u{1b}"),
            (kVK_Delete, "Backspace", "⌫", "\u{8}"),
            (kVK_ForwardDelete, "Delete", "⌦", fn(NSDeleteFunctionKey)),
            (kVK_Help, "Insert", "Help", fn(NSHelpFunctionKey)),
            (kVK_ANSI_Keypad0, "Num0", "0", "0"), (kVK_ANSI_Keypad1, "Num1", "1", "1"),
            (kVK_ANSI_Keypad2, "Num2", "2", "2"), (kVK_ANSI_Keypad3, "Num3", "3", "3"),
            (kVK_ANSI_Keypad4, "Num4", "4", "4"), (kVK_ANSI_Keypad5, "Num5", "5", "5"),
            (kVK_ANSI_Keypad6, "Num6", "6", "6"), (kVK_ANSI_Keypad7, "Num7", "7", "7"),
            (kVK_ANSI_Keypad8, "Num8", "8", "8"), (kVK_ANSI_Keypad9, "Num9", "9", "9"),
            (kVK_ANSI_KeypadDecimal, "Num.", ".", "."), (kVK_ANSI_KeypadMultiply, "Num*", "*", "*"),
            (kVK_ANSI_KeypadPlus, "Num+", "+", "+"), (kVK_ANSI_KeypadMinus, "Num-", "-", "-"),
            (kVK_ANSI_KeypadDivide, "Num/", "/", "/"), (kVK_ANSI_KeypadEquals, "Num=", "=", "="),
            (kVK_ANSI_KeypadEnter, "NumEnter", "⌤", "\u{3}"), (kVK_ANSI_KeypadClear, "NumLock", "⌧", fn(NSClearLineFunctionKey)),
        ]
        for (c, n, s, e) in named { t.append(Info(code: c, name: n, symbol: s, equivalent: e)) }
        return t
    }()

    static func info(_ code: UInt16) -> Info? { table.first { $0.code == Int(code) } }

    static func name(_ code: UInt16) -> String { info(code)?.name ?? String(format: "VK%02X", code) }

    static func symbol(_ code: UInt16) -> String { info(code)?.symbol ?? String(format: "VK%02X", code) }

    static func fromName(_ name: String) -> UInt16? {
        if let i = table.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return UInt16(i.code)
        }
        let up = name.uppercased()
        if up.hasPrefix("VK"), let v = UInt16(up.dropFirst(2), radix: 16) { return v }
        return nil
    }

    static func isFunctionKey(_ code: UInt16) -> Bool { info(code)?.name.range(of: #"^F\d+$"#, options: .regularExpression) != nil }
}

func hotkeyToString(_ mods: Modifiers, _ key: UInt16?) -> String {
    guard let key else { return "" }
    let prefix = Modifiers.ordered.filter { mods.contains($0.0) }.map { $0.config + "+" }.joined()
    return prefix + KeyCode.name(key)
}

/// "⌃⌥⌘→" for the UI.
func hotkeyDisplay(_ mods: Modifiers, _ key: UInt16?) -> String {
    guard let key else { return "" }
    return mods.symbols + KeyCode.symbol(key)
}

/// Parses "Ctrl+Opt+Cmd+Right". Also accepts the Windows names Alt and Win (= Cmd).
/// Returns ([], nil) for an empty string, nil when the text is not understood.
func parseHotkey(_ s: String) -> (Modifiers, UInt16?)? {
    var rest = Substring(s.trimmingCharacters(in: .whitespaces))
    if rest.isEmpty { return ([], nil) }
    let prefixes: [(Modifiers, String)] = [
        (.control, "ctrl+"), (.control, "control+"), (.option, "opt+"), (.option, "option+"), (.option, "alt+"),
        (.shift, "shift+"), (.command, "cmd+"), (.command, "command+"), (.command, "win+"),
    ]
    var mods: Modifiers = []
    outer: while true {
        for (bit, prefix) in prefixes where rest.count > prefix.count && rest.lowercased().hasPrefix(prefix) {
            mods.insert(bit)
            rest = rest.dropFirst(prefix.count).drop { $0 == " " }
            continue outer
        }
        break
    }
    guard let key = KeyCode.fromName(rest.trimmingCharacters(in: .whitespaces)) else { return nil }
    return (mods, key)
}
