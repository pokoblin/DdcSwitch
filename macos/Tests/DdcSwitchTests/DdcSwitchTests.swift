import XCTest
@testable import DdcSwitch

final class ConfigTests: XCTestCase {
    func testHotkeyRoundtrip() {
        let cases: [(Modifiers, UInt16)] = [
            ([.control, .option, .command], KeyCode.right),
            ([.shift], UInt16(KeyCode.fromName("Num+")!)),
            ([], UInt16(KeyCode.fromName("F12")!)),
            ([.option], UInt16(KeyCode.fromName("A")!)),
        ]
        for (mods, key) in cases {
            let s = hotkeyToString(mods, key)
            let parsed = parseHotkey(s)
            XCTAssertEqual(parsed?.0, mods, s)
            XCTAssertEqual(parsed?.1, key, s)
        }
        XCTAssertEqual(hotkeyToString([.control, .option, .command], KeyCode.right), "Ctrl+Opt+Cmd+Right")
        XCTAssertEqual(hotkeyDisplay([.command, .control, .option], KeyCode.left), "⌃⌥⌘←")
    }

    func testWindowsHotkeyNames() {
        // A config.ini written by the Windows version: Alt = Option, Win = Command.
        let parsed = parseHotkey("ctrl+alt+win+pageup")
        XCTAssertEqual(parsed?.0, [.control, .option, .command])
        XCTAssertEqual(parsed?.1, KeyCode.fromName("PageUp"))
        XCTAssertEqual(parseHotkey("").map { $0.1 } ?? 1, nil)
        XCTAssertNil(parseHotkey("Ctrl+Nonsense"))
    }

    func testInputParsing() {
        XCTAssertEqual(parseInput("25"), 25)
        XCTAssertEqual(parseInput("0x19"), 25)
        XCTAssertEqual(parseInput("17 - HDMI-1"), 17)
        XCTAssertEqual(parseInput("25 (0x19)"), 25)
        XCTAssertEqual(parseInput("hdmi1"), 17)
        XCTAssertNil(parseInput(""))
        XCTAssertNil(parseInput("abc"))
        XCTAssertEqual(inputLabel(17), "17 - HDMI-1")
        XCTAssertEqual(inputLabel(25), "25 (0x19)")
    }

    func testConfigRoundtrip() throws {
        var cfg = Config()
        cfg.monitor = 2
        cfg.monitorName = "DELL U2725QE"
        cfg.bindings[2] = HotkeyBinding(enabled: true, name: "Laptop", input: 0x19, mods: [.shift, .command], key: KeyCode.fromName("F5"))
        cfg.shutdownInput = 25
        cfg.sleepSwitch = true
        cfg.language = "zh-Hans"
        cfg.appearance = "dark"
        var parsed = Config()
        parsed.parse(cfg.serialized())
        XCTAssertEqual(parsed, cfg)
    }

    func testReadsWindowsConfig() {
        var cfg = Config()
        cfg.parse("\u{feff}# DdcSwitch\r\nmonitor = 1\r\nhotkey1 = Ctrl+Alt+Win+Right\r\nhotkey1_input = usbc\r\nshutdown_switch = false\r\n")
        XCTAssertEqual(cfg.bindings[0].mods, [.control, .option, .command])
        XCTAssertEqual(cfg.bindings[0].key, KeyCode.right)
        XCTAssertEqual(cfg.bindings[0].input, 27)
        XCTAssertFalse(cfg.shutdownSwitch)
    }

    func testInputTitle() {
        let cfg = Config()
        XCTAssertEqual(cfg.inputTitle(17), "Windows (HDMI-1) [17]")
        XCTAssertEqual(cfg.inputTitle(15), "15 - DP-1")
    }
}

final class DDCTests: XCTestCase {
    func testCapsInputs() {
        let caps = "(prot(monitor)type(lcd)model(U2725QE)cmds(01 02)vcp(02 04 14(01 04 05) 16 60( 19 0F 11) 66(00F2) E2(00 02))mccs_ver(2.1))"
        XCTAssertEqual(DDC.parseInputCaps(caps), [0x19, 0x0F, 0x11])
        XCTAssertTrue(DDC.parseInputCaps("vcp(10 12)").isEmpty)
        XCTAssertTrue(DDC.parseInputCaps("(prot(monitor)vcp(02)mccs_ver(2.2))").isEmpty)
    }

    func testReplyChecksum() {
        // Get VCP 0x60 replies captured from a Dell U2725QE and a portable monitor.
        XCTAssertTrue(DDC.checksumOK([0x6E, 0x88, 0x02, 0x00, 0x60, 0x00, 0x00, 0x0E, 0x19, 0x19, 0xDA], length: 11))
        XCTAssertTrue(DDC.checksumOK([0x6E, 0x88, 0x02, 0x00, 0x60, 0x00, 0x00, 0x03, 0x00, 0x10, 0xC7], length: 11))
        XCTAssertFalse(DDC.checksumOK([0x6E, 0x88, 0x02, 0x00, 0x60, 0x00, 0x00, 0x0E, 0x19, 0x18, 0xDA], length: 11))
    }
}

final class I18nTests: XCTestCase {
    private func fields(_ s: Strings) -> [(String, String)] {
        Mirror(reflecting: s).children.map { ($0.label ?? "", $0.value as? String ?? "") }
    }

    private func placeholders(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"\{\d\}"#)
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }.sorted()
    }

    func testPlaceholdersMatchEnglish() {
        let en = fields(I18n.en)
        for (code, strings) in I18n.languages {
            for ((key, english), (_, translated)) in zip(en, fields(strings)) {
                XCTAssertFalse(translated.isEmpty, "\(code).\(key) is empty")
                XCTAssertEqual(placeholders(translated), placeholders(english), "\(code).\(key)")
            }
        }
    }

    func testSystemLanguage() {
        func code(_ prefs: [String]) -> String { I18n.languages[I18n.systemLanguage(prefs)].code }
        XCTAssertEqual(code(["zh-Hans-CN"]), "zh-Hans")
        XCTAssertEqual(code(["zh-Hant-TW"]), "zh-Hant")
        XCTAssertEqual(code(["zh-HK"]), "zh-Hant")
        XCTAssertEqual(code(["pt-PT"]), "pt-BR")
        XCTAssertEqual(code(["nl-NL", "de-DE"]), "de")
        XCTAssertEqual(code(["nl-NL"]), "en")
    }

    func testFmt() {
        XCTAssertEqual(I18n.fmt("{0} → {1}", "A", 2), "A → 2")
    }
}
