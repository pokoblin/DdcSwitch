// User interface translations. Every language is a `Strings` value, so the compiler refuses a
// translation that misses a string. Placeholders are `{0}`, `{1}`, ... and are filled in with `fmt`.
//
// To add a language: copy `en`, translate it, and add it to `I18n.languages`.

import Foundation

struct Strings {
    /// Name of the language in that language, shown in the language picker.
    let langName: String
    let appTagline: String

    // menu bar menu & notifications
    let menuSwitchTo: String
    let menuNoHotkeys: String
    let menuShutdownSwitch: String
    let menuLaunchAtLogin: String
    let menuSettings: String
    let menuOpenLog: String
    let menuQuit: String
    let menuAbout: String
    let aboutDescription: String
    let switchedTitle: String
    let switchFailedTitle: String
    let hotkeysFailedTitle: String
    let hotkeyInUse: String
    let launchAtLoginFailed: String
    let saveFailed: String

    // DDC/CI errors
    let errMonitorNotFound: String
    let errSetFailed: String
    let errReadFailed: String
    let errCapsFailed: String

    // settings window
    let paneGeneral: String
    let paneMonitor: String
    let paneShortcuts: String
    let panePower: String

    let launchAtLogin: String
    let launchAtLoginFooter: String
    let loginNeedsApproval: String
    let openLoginItems: String
    let notifySuccess: String
    let notifyFooter: String
    let language: String
    let langAuto: String
    let appearance: String
    let appearanceAuto: String
    let appearanceLight: String
    let appearanceDark: String
    let log: String
    let openLog: String
    let configFile: String
    let showInFinder: String
    let version: String

    let monitor: String
    let noMonitors: String
    let detectAgain: String
    let currentInput: String
    let reportedInputs: String
    let reading: String
    let notReported: String
    let monitorFooter: String

    let shortcutRow: String
    let enabled: String
    let name: String
    let namePrompt: String
    let targetInput: String
    let shortcut: String
    let recordShortcut: String
    let typeShortcut: String
    let clearShortcut: String
    let shortcutsFooter: String
    let errRowInput: String
    let errRowNoHotkey: String
    let errRowModifier: String
    let errRowDuplicate: String

    let switchTo: String
    let beforeShutdown: String
    let skipOnRestart: String
    let beforeSleep: String
    let powerFooter: String
    let errShutdownInput: String
    let notRunningAtLogin: String
    let turnOnLaunchAtLogin: String
}

enum I18n {
    /// (code stored in config.ini, strings) – same codes as the Windows version.
    static let languages: [(code: String, strings: Strings)] = [
        ("en", en), ("zh-Hans", zhHans), ("zh-Hant", zhHant), ("ja", ja), ("ko", ko),
        ("es", es), ("fr", fr), ("de", de), ("pt-BR", ptBR), ("ru", ru),
    ]

    private static var current = 0

    /// Strings of the active language.
    static var t: Strings { languages[current].strings }

    /// Code of the active language, e.g. "zh-Hans".
    static var currentCode: String { languages[current].code }

    /// Activates the language from the config ("auto" or a code from `languages`).
    static func apply(_ setting: String) {
        let wanted = setting.trimmingCharacters(in: .whitespaces)
        current = languages.firstIndex { $0.code.caseInsensitiveCompare(wanted) == .orderedSame } ?? systemLanguage()
    }

    static func systemLanguage(_ preferred: [String] = Locale.preferredLanguages) -> Int {
        for pref in preferred {
            let p = pref.lowercased()
            let code: String
            if p.hasPrefix("zh-hant") || p.hasPrefix("zh-tw") || p.hasPrefix("zh-hk") || p.hasPrefix("zh-mo") {
                code = "zh-Hant"
            } else if p.hasPrefix("zh") {
                code = "zh-Hans"
            } else if p.hasPrefix("pt") {
                code = "pt-BR"
            } else {
                code = String(p.prefix(2))
            }
            if let i = languages.firstIndex(where: { $0.code == code }) { return i }
        }
        return 0
    }

    /// Replaces `{0}`, `{1}`, ... in `template`.
    static func fmt(_ template: String, _ args: Any...) -> String {
        var s = template
        for (i, a) in args.enumerated() {
            s = s.replacingOccurrences(of: "{\(i)}", with: "\(a)")
        }
        return s
    }
}

// ---------------------------------------------------------------------------

extension I18n {
    static let en = Strings(
        langName: "English",
        appTagline: "DdcSwitch – monitor input switcher",
        menuSwitchTo: "Switch to {0}",
        menuNoHotkeys: "No Shortcuts Set Up",
        menuShutdownSwitch: "Switch to {0} Before Shutdown",
        menuLaunchAtLogin: "Launch at Login",
        menuSettings: "Settings…",
        menuOpenLog: "Open Log",
        menuQuit: "Quit DdcSwitch",
        menuAbout: "About DdcSwitch",
        aboutDescription: "Switches your monitor's input source over DDC/CI – with a keyboard shortcut, or right before your Mac shuts down.",
        switchedTitle: "Input Switched",
        switchFailedTitle: "Couldn't Switch Input",
        hotkeysFailedTitle: "Some Shortcuts Couldn't Be Registered",
        hotkeyInUse: "{0} is already used by another app.",
        launchAtLoginFailed: "Couldn't change Launch at Login: {0}",
        saveFailed: "Couldn't save settings: {0}",
        errMonitorNotFound: "Monitor #{0} not found ({1} DDC/CI monitor(s) detected)",
        errSetFailed: "{0}: switching the input failed (error {1})",
        errReadFailed: "{0}: reading the input failed (error {1})",
        errCapsFailed: "{0}: couldn't read capabilities (is DDC/CI enabled in the monitor menu?)",
        paneGeneral: "General",
        paneMonitor: "Monitor",
        paneShortcuts: "Shortcuts",
        panePower: "Shutdown & Sleep",
        launchAtLogin: "Launch at login",
        launchAtLoginFooter: "DdcSwitch has to be running to switch before shutdown or sleep.",
        loginNeedsApproval: "Needs your approval in System Settings.",
        openLoginItems: "Open Login Items…",
        notifySuccess: "Notify after every switch",
        notifyFooter: "Failures are always shown.",
        language: "Language",
        langAuto: "System Language",
        appearance: "Appearance",
        appearanceAuto: "System",
        appearanceLight: "Light",
        appearanceDark: "Dark",
        log: "Log",
        openLog: "Open Log",
        configFile: "Settings file",
        showInFinder: "Show in Finder",
        version: "Version {0}",
        monitor: "Monitor",
        noMonitors: "No DDC/CI monitor detected",
        detectAgain: "Detect Again",
        currentInput: "Current input",
        reportedInputs: "Reported inputs",
        reading: "Reading…",
        notReported: "Not reported",
        monitorFooter: "Input codes follow the VESA MCCS standard (15 DP-1, 16 DP-2, 17 HDMI-1, 18 HDMI-2, 27 USB-C), but vendors deviate: a Dell U2725QE uses 25 for USB-C.",
        shortcutRow: "Shortcut {0}",
        enabled: "Enabled",
        name: "Name",
        namePrompt: "e.g. Windows PC",
        targetInput: "Target input",
        shortcut: "Shortcut",
        recordShortcut: "Record Shortcut",
        typeShortcut: "Type Shortcut…",
        clearShortcut: "Clear Shortcut",
        shortcutsFooter: "Shortcuts work in every app while DdcSwitch is running. Press Esc to cancel recording.",
        errRowInput: "\"{0}\" is not a valid input. Enter a number such as 17.",
        errRowNoHotkey: "Record a shortcut, or turn this row off.",
        errRowModifier: "The shortcut needs at least one of ⌃ ⌥ ⇧ ⌘.",
        errRowDuplicate: "{0} is used by more than one row.",
        switchTo: "Switch to",
        beforeShutdown: "Before shutdown",
        skipOnRestart: "Not when restarting",
        beforeSleep: "Before sleep",
        powerFooter: "DdcSwitch switches the input when macOS quits apps to shut down. Restarts and logging out are recognised; logging out never switches.",
        errShutdownInput: "\"{0}\" is not a valid input.",
        notRunningAtLogin: "DdcSwitch doesn't launch at login, so it can only switch while you keep it running.",
        turnOnLaunchAtLogin: "Turn On"
    )

    static let zhHans = Strings(
        langName: "简体中文",
        appTagline: "DdcSwitch 显示器输入源切换",
        menuSwitchTo: "切换到 {0}",
        menuNoHotkeys: "尚未设置快捷键",
        menuShutdownSwitch: "关机前切换到 {0}",
        menuLaunchAtLogin: "登录时启动",
        menuSettings: "设置…",
        menuOpenLog: "打开日志",
        menuQuit: "退出 DdcSwitch",
        menuAbout: "关于 DdcSwitch",
        aboutDescription: "通过 DDC/CI 切换显示器输入源——按快捷键，或在 Mac 关机前自动切换。",
        switchedTitle: "已切换输入源",
        switchFailedTitle: "无法切换输入源",
        hotkeysFailedTitle: "部分快捷键无法注册",
        hotkeyInUse: "{0} 已被其他应用占用。",
        launchAtLoginFailed: "无法更改“登录时启动”：{0}",
        saveFailed: "无法保存设置：{0}",
        errMonitorNotFound: "未找到 {0} 号显示器（检测到 {1} 台 DDC/CI 显示器）",
        errSetFailed: "{0}：切换输入源失败（错误码 {1}）",
        errReadFailed: "{0}：读取输入源失败（错误码 {1}）",
        errCapsFailed: "{0}：无法读取显示器能力（请确认显示器菜单中已开启 DDC/CI）",
        paneGeneral: "通用",
        paneMonitor: "显示器",
        paneShortcuts: "快捷键",
        panePower: "关机与睡眠",
        launchAtLogin: "登录时启动",
        launchAtLoginFooter: "DdcSwitch 需要保持运行，才能在关机或睡眠前切换。",
        loginNeedsApproval: "需要在“系统设置”中批准。",
        openLoginItems: "打开登录项…",
        notifySuccess: "每次切换后都显示通知",
        notifyFooter: "切换失败时总会通知。",
        language: "语言",
        langAuto: "跟随系统",
        appearance: "外观",
        appearanceAuto: "跟随系统",
        appearanceLight: "浅色",
        appearanceDark: "深色",
        log: "日志",
        openLog: "打开日志",
        configFile: "设置文件",
        showInFinder: "在访达中显示",
        version: "版本 {0}",
        monitor: "显示器",
        noMonitors: "未检测到 DDC/CI 显示器",
        detectAgain: "重新检测",
        currentInput: "当前输入源",
        reportedInputs: "显示器报告支持",
        reading: "正在读取…",
        notReported: "未报告",
        monitorFooter: "输入源代码遵循 VESA MCCS 标准（15 DP-1、16 DP-2、17 HDMI-1、18 HDMI-2、27 USB-C），但各厂商可能不同：Dell U2725QE 的 USB-C 是 25。",
        shortcutRow: "快捷键 {0}",
        enabled: "启用",
        name: "名称",
        namePrompt: "例如 Windows 电脑",
        targetInput: "目标输入源",
        shortcut: "快捷键",
        recordShortcut: "录制快捷键",
        typeShortcut: "请按下快捷键…",
        clearShortcut: "清除快捷键",
        shortcutsFooter: "DdcSwitch 运行时，快捷键在任何应用中都有效。录制时按 Esc 取消。",
        errRowInput: "“{0}”不是有效的输入源，请输入数字，例如 17。",
        errRowNoHotkey: "请录制快捷键，或关闭这一行。",
        errRowModifier: "快捷键至少需要 ⌃ ⌥ ⇧ ⌘ 之一。",
        errRowDuplicate: "{0} 被多行同时使用。",
        switchTo: "切换到",
        beforeShutdown: "关机前",
        skipOnRestart: "重新启动时不切换",
        beforeSleep: "睡眠前",
        powerFooter: "macOS 为关机而退出各应用时，DdcSwitch 会切换输入源。可识别重新启动和退出登录，退出登录时从不切换。",
        errShutdownInput: "“{0}”不是有效的输入源。",
        notRunningAtLogin: "DdcSwitch 未设为登录时启动，只有在它运行时才能切换。",
        turnOnLaunchAtLogin: "开启"
    )

    static let zhHant = Strings(
        langName: "繁體中文",
        appTagline: "DdcSwitch 螢幕輸入來源切換",
        menuSwitchTo: "切換到 {0}",
        menuNoHotkeys: "尚未設定快速鍵",
        menuShutdownSwitch: "關機前切換到 {0}",
        menuLaunchAtLogin: "登入時啟動",
        menuSettings: "設定…",
        menuOpenLog: "開啟記錄",
        menuQuit: "結束 DdcSwitch",
        menuAbout: "關於 DdcSwitch",
        aboutDescription: "透過 DDC/CI 切換螢幕輸入來源——按快速鍵，或在 Mac 關機前自動切換。",
        switchedTitle: "已切換輸入來源",
        switchFailedTitle: "無法切換輸入來源",
        hotkeysFailedTitle: "部分快速鍵無法註冊",
        hotkeyInUse: "{0} 已被其他 App 使用。",
        launchAtLoginFailed: "無法變更「登入時啟動」：{0}",
        saveFailed: "無法儲存設定：{0}",
        errMonitorNotFound: "找不到第 {0} 台螢幕（偵測到 {1} 台 DDC/CI 螢幕）",
        errSetFailed: "{0}：切換輸入來源失敗（錯誤碼 {1}）",
        errReadFailed: "{0}：讀取輸入來源失敗（錯誤碼 {1}）",
        errCapsFailed: "{0}：無法讀取螢幕功能（請確認螢幕選單中已開啟 DDC/CI）",
        paneGeneral: "一般",
        paneMonitor: "螢幕",
        paneShortcuts: "快速鍵",
        panePower: "關機與睡眠",
        launchAtLogin: "登入時啟動",
        launchAtLoginFooter: "DdcSwitch 必須保持執行，才能在關機或睡眠前切換。",
        loginNeedsApproval: "需要在「系統設定」中允許。",
        openLoginItems: "打開登入項目…",
        notifySuccess: "每次切換後都顯示通知",
        notifyFooter: "切換失敗時一律通知。",
        language: "語言",
        langAuto: "跟隨系統",
        appearance: "外觀",
        appearanceAuto: "跟隨系統",
        appearanceLight: "淺色",
        appearanceDark: "深色",
        log: "記錄",
        openLog: "開啟記錄",
        configFile: "設定檔",
        showInFinder: "在 Finder 中顯示",
        version: "版本 {0}",
        monitor: "螢幕",
        noMonitors: "未偵測到 DDC/CI 螢幕",
        detectAgain: "重新偵測",
        currentInput: "目前輸入來源",
        reportedInputs: "螢幕回報支援",
        reading: "正在讀取…",
        notReported: "未回報",
        monitorFooter: "輸入來源代碼遵循 VESA MCCS 標準（15 DP-1、16 DP-2、17 HDMI-1、18 HDMI-2、27 USB-C），但各廠商可能不同：Dell U2725QE 的 USB-C 是 25。",
        shortcutRow: "快速鍵 {0}",
        enabled: "啟用",
        name: "名稱",
        namePrompt: "例如 Windows 電腦",
        targetInput: "目標輸入來源",
        shortcut: "快速鍵",
        recordShortcut: "錄製快速鍵",
        typeShortcut: "請按下快速鍵…",
        clearShortcut: "清除快速鍵",
        shortcutsFooter: "DdcSwitch 執行時，快速鍵在任何 App 中都有效。錄製時按 Esc 取消。",
        errRowInput: "「{0}」不是有效的輸入來源，請輸入數字，例如 17。",
        errRowNoHotkey: "請錄製快速鍵，或關閉這一列。",
        errRowModifier: "快速鍵至少需要 ⌃ ⌥ ⇧ ⌘ 其中之一。",
        errRowDuplicate: "{0} 被多列同時使用。",
        switchTo: "切換到",
        beforeShutdown: "關機前",
        skipOnRestart: "重新啟動時不切換",
        beforeSleep: "睡眠前",
        powerFooter: "macOS 為關機而結束各 App 時，DdcSwitch 會切換輸入來源。可辨識重新啟動與登出，登出時一律不切換。",
        errShutdownInput: "「{0}」不是有效的輸入來源。",
        notRunningAtLogin: "DdcSwitch 未設為登入時啟動，只有在它執行時才能切換。",
        turnOnLaunchAtLogin: "開啟"
    )

    static let ja = Strings(
        langName: "日本語",
        appTagline: "DdcSwitch – モニター入力切り替え",
        menuSwitchTo: "{0} に切り替え",
        menuNoHotkeys: "ショートカット未設定",
        menuShutdownSwitch: "シャットダウン前に {0} に切り替え",
        menuLaunchAtLogin: "ログイン時に起動",
        menuSettings: "設定…",
        menuOpenLog: "ログを開く",
        menuQuit: "DdcSwitch を終了",
        menuAbout: "DdcSwitch について",
        aboutDescription: "DDC/CI でモニターの入力を切り替えます――ショートカットで、または Mac のシャットダウン直前に自動で。",
        switchedTitle: "入力を切り替えました",
        switchFailedTitle: "入力を切り替えられませんでした",
        hotkeysFailedTitle: "一部のショートカットを登録できませんでした",
        hotkeyInUse: "{0} は別のアプリで使用されています。",
        launchAtLoginFailed: "「ログイン時に起動」を変更できませんでした: {0}",
        saveFailed: "設定を保存できませんでした: {0}",
        errMonitorNotFound: "モニター #{0} が見つかりません（DDC/CI モニターを {1} 台検出）",
        errSetFailed: "{0}: 入力の切り替えに失敗しました（エラー {1}）",
        errReadFailed: "{0}: 入力の読み取りに失敗しました（エラー {1}）",
        errCapsFailed: "{0}: 機能情報を読み取れません（モニターのメニューで DDC/CI が有効か確認してください）",
        paneGeneral: "一般",
        paneMonitor: "モニター",
        paneShortcuts: "ショートカット",
        panePower: "シャットダウンとスリープ",
        launchAtLogin: "ログイン時に起動",
        launchAtLoginFooter: "シャットダウンやスリープの前に切り替えるには、DdcSwitch が起動している必要があります。",
        loginNeedsApproval: "システム設定での許可が必要です。",
        openLoginItems: "ログイン項目を開く…",
        notifySuccess: "切り替えるたびに通知",
        notifyFooter: "失敗した場合は常に通知されます。",
        language: "言語",
        langAuto: "システムの言語",
        appearance: "外観モード",
        appearanceAuto: "システムに合わせる",
        appearanceLight: "ライト",
        appearanceDark: "ダーク",
        log: "ログ",
        openLog: "ログを開く",
        configFile: "設定ファイル",
        showInFinder: "Finder に表示",
        version: "バージョン {0}",
        monitor: "モニター",
        noMonitors: "DDC/CI モニターが見つかりません",
        detectAgain: "再検出",
        currentInput: "現在の入力",
        reportedInputs: "モニターの対応入力",
        reading: "読み取り中…",
        notReported: "報告なし",
        monitorFooter: "入力コードは VESA MCCS 規格に従います（15 DP-1、16 DP-2、17 HDMI-1、18 HDMI-2、27 USB-C）が、メーカーによって異なります。Dell U2725QE では USB-C が 25 です。",
        shortcutRow: "ショートカット {0}",
        enabled: "有効",
        name: "名前",
        namePrompt: "例: Windows PC",
        targetInput: "切り替え先の入力",
        shortcut: "ショートカット",
        recordShortcut: "ショートカットを記録",
        typeShortcut: "キーを入力…",
        clearShortcut: "ショートカットを消去",
        shortcutsFooter: "DdcSwitch の起動中は、どのアプリでもショートカットが使えます。記録中に Esc を押すとキャンセルします。",
        errRowInput: "「{0}」は有効な入力ではありません。17 などの数値を入力してください。",
        errRowNoHotkey: "ショートカットを記録するか、この行をオフにしてください。",
        errRowModifier: "ショートカットには ⌃ ⌥ ⇧ ⌘ のいずれかが必要です。",
        errRowDuplicate: "{0} が複数の行で使われています。",
        switchTo: "切り替え先",
        beforeShutdown: "シャットダウン前",
        skipOnRestart: "再起動時は切り替えない",
        beforeSleep: "スリープ前",
        powerFooter: "macOS がシャットダウンのためにアプリを終了するとき、DdcSwitch が入力を切り替えます。再起動とログアウトは判別され、ログアウト時は切り替えません。",
        errShutdownInput: "「{0}」は有効な入力ではありません。",
        notRunningAtLogin: "DdcSwitch はログイン時に起動しないため、起動中にしか切り替えられません。",
        turnOnLaunchAtLogin: "オンにする"
    )

    static let ko = Strings(
        langName: "한국어",
        appTagline: "DdcSwitch – 모니터 입력 전환",
        menuSwitchTo: "{0}(으)로 전환",
        menuNoHotkeys: "설정된 단축키 없음",
        menuShutdownSwitch: "시스템 종료 전에 {0}(으)로 전환",
        menuLaunchAtLogin: "로그인 시 실행",
        menuSettings: "설정…",
        menuOpenLog: "로그 열기",
        menuQuit: "DdcSwitch 종료",
        menuAbout: "DdcSwitch에 관하여",
        aboutDescription: "DDC/CI로 모니터 입력 소스를 전환합니다. 단축키로, 또는 Mac이 종료되기 직전에 자동으로.",
        switchedTitle: "입력이 전환됨",
        switchFailedTitle: "입력을 전환할 수 없음",
        hotkeysFailedTitle: "일부 단축키를 등록할 수 없음",
        hotkeyInUse: "{0}은(는) 다른 앱에서 이미 사용 중입니다.",
        launchAtLoginFailed: "'로그인 시 실행'을 변경할 수 없음: {0}",
        saveFailed: "설정을 저장할 수 없음: {0}",
        errMonitorNotFound: "모니터 #{0}을(를) 찾을 수 없습니다(DDC/CI 모니터 {1}대 감지됨)",
        errSetFailed: "{0}: 입력 전환 실패(오류 {1})",
        errReadFailed: "{0}: 입력 읽기 실패(오류 {1})",
        errCapsFailed: "{0}: 기능 정보를 읽을 수 없습니다(모니터 메뉴에서 DDC/CI가 켜져 있는지 확인하세요)",
        paneGeneral: "일반",
        paneMonitor: "모니터",
        paneShortcuts: "단축키",
        panePower: "종료 및 잠자기",
        launchAtLogin: "로그인 시 실행",
        launchAtLoginFooter: "시스템 종료나 잠자기 전에 전환하려면 DdcSwitch가 실행 중이어야 합니다.",
        loginNeedsApproval: "시스템 설정에서 승인이 필요합니다.",
        openLoginItems: "로그인 항목 열기…",
        notifySuccess: "전환할 때마다 알림",
        notifyFooter: "실패는 항상 알립니다.",
        language: "언어",
        langAuto: "시스템 언어",
        appearance: "모양",
        appearanceAuto: "시스템 설정에 따름",
        appearanceLight: "라이트",
        appearanceDark: "다크",
        log: "로그",
        openLog: "로그 열기",
        configFile: "설정 파일",
        showInFinder: "Finder에서 보기",
        version: "버전 {0}",
        monitor: "모니터",
        noMonitors: "DDC/CI 모니터가 감지되지 않음",
        detectAgain: "다시 감지",
        currentInput: "현재 입력",
        reportedInputs: "모니터 지원 입력",
        reading: "읽는 중…",
        notReported: "보고되지 않음",
        monitorFooter: "입력 코드는 VESA MCCS 표준을 따르지만(15 DP-1, 16 DP-2, 17 HDMI-1, 18 HDMI-2, 27 USB-C) 제조사마다 다를 수 있습니다. Dell U2725QE는 USB-C에 25를 사용합니다.",
        shortcutRow: "단축키 {0}",
        enabled: "사용",
        name: "이름",
        namePrompt: "예: Windows PC",
        targetInput: "전환할 입력",
        shortcut: "단축키",
        recordShortcut: "단축키 기록",
        typeShortcut: "단축키 입력…",
        clearShortcut: "단축키 지우기",
        shortcutsFooter: "DdcSwitch가 실행 중이면 모든 앱에서 단축키를 사용할 수 있습니다. 기록 중 Esc를 누르면 취소됩니다.",
        errRowInput: "\"{0}\"은(는) 올바른 입력이 아닙니다. 17과 같은 숫자를 입력하세요.",
        errRowNoHotkey: "단축키를 기록하거나 이 행을 끄세요.",
        errRowModifier: "단축키에는 ⌃ ⌥ ⇧ ⌘ 중 하나 이상이 필요합니다.",
        errRowDuplicate: "{0}이(가) 여러 행에서 사용됩니다.",
        switchTo: "전환할 입력",
        beforeShutdown: "시스템 종료 전",
        skipOnRestart: "재시동 시에는 전환 안 함",
        beforeSleep: "잠자기 전",
        powerFooter: "macOS가 시스템 종료를 위해 앱을 종료할 때 DdcSwitch가 입력을 전환합니다. 재시동과 로그아웃을 구분하며, 로그아웃 시에는 전환하지 않습니다.",
        errShutdownInput: "\"{0}\"은(는) 올바른 입력이 아닙니다.",
        notRunningAtLogin: "DdcSwitch가 로그인 시 실행되지 않으므로 실행 중일 때만 전환할 수 있습니다.",
        turnOnLaunchAtLogin: "켜기"
    )

    static let es = Strings(
        langName: "Español",
        appTagline: "DdcSwitch – cambia la entrada del monitor",
        menuSwitchTo: "Cambiar a {0}",
        menuNoHotkeys: "No hay atajos configurados",
        menuShutdownSwitch: "Cambiar a {0} antes de apagar",
        menuLaunchAtLogin: "Abrir al iniciar sesión",
        menuSettings: "Ajustes…",
        menuOpenLog: "Abrir registro",
        menuQuit: "Salir de DdcSwitch",
        menuAbout: "Acerca de DdcSwitch",
        aboutDescription: "Cambia la entrada del monitor por DDC/CI: con un atajo de teclado o justo antes de que el Mac se apague.",
        switchedTitle: "Entrada cambiada",
        switchFailedTitle: "No se pudo cambiar la entrada",
        hotkeysFailedTitle: "Algunos atajos no se pudieron registrar",
        hotkeyInUse: "Otra app ya usa {0}.",
        launchAtLoginFailed: "No se pudo cambiar «Abrir al iniciar sesión»: {0}",
        saveFailed: "No se pudieron guardar los ajustes: {0}",
        errMonitorNotFound: "No se encontró el monitor n.º {0} ({1} monitor(es) DDC/CI detectado(s))",
        errSetFailed: "{0}: no se pudo cambiar la entrada (error {1})",
        errReadFailed: "{0}: no se pudo leer la entrada (error {1})",
        errCapsFailed: "{0}: no se pudieron leer las capacidades (¿está DDC/CI activado en el menú del monitor?)",
        paneGeneral: "General",
        paneMonitor: "Monitor",
        paneShortcuts: "Atajos",
        panePower: "Apagado y reposo",
        launchAtLogin: "Abrir al iniciar sesión",
        launchAtLoginFooter: "DdcSwitch tiene que estar abierto para cambiar antes de apagar o entrar en reposo.",
        loginNeedsApproval: "Requiere tu aprobación en Ajustes del Sistema.",
        openLoginItems: "Abrir ítems de inicio…",
        notifySuccess: "Notificar cada cambio",
        notifyFooter: "Los errores siempre se notifican.",
        language: "Idioma",
        langAuto: "Idioma del sistema",
        appearance: "Apariencia",
        appearanceAuto: "Sistema",
        appearanceLight: "Claro",
        appearanceDark: "Oscuro",
        log: "Registro",
        openLog: "Abrir registro",
        configFile: "Archivo de ajustes",
        showInFinder: "Mostrar en el Finder",
        version: "Versión {0}",
        monitor: "Monitor",
        noMonitors: "No se detectó ningún monitor DDC/CI",
        detectAgain: "Volver a detectar",
        currentInput: "Entrada actual",
        reportedInputs: "Entradas que indica el monitor",
        reading: "Leyendo…",
        notReported: "No indicadas",
        monitorFooter: "Los códigos siguen el estándar VESA MCCS (15 DP-1, 16 DP-2, 17 HDMI-1, 18 HDMI-2, 27 USB-C), pero algunos fabricantes usan otros: un Dell U2725QE usa 25 para USB-C.",
        shortcutRow: "Atajo {0}",
        enabled: "Activado",
        name: "Nombre",
        namePrompt: "p. ej., PC con Windows",
        targetInput: "Entrada de destino",
        shortcut: "Atajo",
        recordShortcut: "Grabar atajo",
        typeShortcut: "Pulsa el atajo…",
        clearShortcut: "Borrar atajo",
        shortcutsFooter: "Los atajos funcionan en cualquier app mientras DdcSwitch está abierto. Pulsa Esc para cancelar la grabación.",
        errRowInput: "«{0}» no es una entrada válida. Escribe un número, como 17.",
        errRowNoHotkey: "Graba un atajo o desactiva esta fila.",
        errRowModifier: "El atajo necesita al menos una de ⌃ ⌥ ⇧ ⌘.",
        errRowDuplicate: "{0} se usa en más de una fila.",
        switchTo: "Cambiar a",
        beforeShutdown: "Antes de apagar",
        skipOnRestart: "No al reiniciar",
        beforeSleep: "Antes del reposo",
        powerFooter: "DdcSwitch cambia la entrada cuando macOS cierra las apps para apagar. Reconoce los reinicios y los cierres de sesión; al cerrar sesión nunca cambia.",
        errShutdownInput: "«{0}» no es una entrada válida.",
        notRunningAtLogin: "DdcSwitch no se abre al iniciar sesión, así que solo puede cambiar mientras esté abierto.",
        turnOnLaunchAtLogin: "Activar"
    )

    static let fr = Strings(
        langName: "Français",
        appTagline: "DdcSwitch – changement d'entrée de l'écran",
        menuSwitchTo: "Basculer vers {0}",
        menuNoHotkeys: "Aucun raccourci configuré",
        menuShutdownSwitch: "Basculer vers {0} avant l'extinction",
        menuLaunchAtLogin: "Ouvrir à la connexion",
        menuSettings: "Réglages…",
        menuOpenLog: "Ouvrir le journal",
        menuQuit: "Quitter DdcSwitch",
        menuAbout: "À propos de DdcSwitch",
        aboutDescription: "Change l'entrée de l'écran via DDC/CI – avec un raccourci clavier ou juste avant l'extinction du Mac.",
        switchedTitle: "Entrée changée",
        switchFailedTitle: "Impossible de changer d'entrée",
        hotkeysFailedTitle: "Certains raccourcis n'ont pas pu être enregistrés",
        hotkeyInUse: "{0} est déjà utilisé par une autre app.",
        launchAtLoginFailed: "Impossible de modifier « Ouvrir à la connexion » : {0}",
        saveFailed: "Impossible d'enregistrer les réglages : {0}",
        errMonitorNotFound: "Écran nº {0} introuvable ({1} écran(s) DDC/CI détecté(s))",
        errSetFailed: "{0} : échec du changement d'entrée (erreur {1})",
        errReadFailed: "{0} : échec de la lecture de l'entrée (erreur {1})",
        errCapsFailed: "{0} : impossible de lire les capacités (DDC/CI est-il activé dans le menu de l'écran ?)",
        paneGeneral: "Général",
        paneMonitor: "Écran",
        paneShortcuts: "Raccourcis",
        panePower: "Extinction et veille",
        launchAtLogin: "Ouvrir à la connexion",
        launchAtLoginFooter: "DdcSwitch doit être ouvert pour basculer avant l'extinction ou la mise en veille.",
        loginNeedsApproval: "Votre autorisation est requise dans Réglages Système.",
        openLoginItems: "Ouvrir les éléments de connexion…",
        notifySuccess: "Notifier chaque changement",
        notifyFooter: "Les échecs sont toujours signalés.",
        language: "Langue",
        langAuto: "Langue du système",
        appearance: "Apparence",
        appearanceAuto: "Système",
        appearanceLight: "Clair",
        appearanceDark: "Sombre",
        log: "Journal",
        openLog: "Ouvrir le journal",
        configFile: "Fichier de réglages",
        showInFinder: "Afficher dans le Finder",
        version: "Version {0}",
        monitor: "Écran",
        noMonitors: "Aucun écran DDC/CI détecté",
        detectAgain: "Redétecter",
        currentInput: "Entrée actuelle",
        reportedInputs: "Entrées signalées",
        reading: "Lecture…",
        notReported: "Non signalées",
        monitorFooter: "Les codes suivent la norme VESA MCCS (15 DP-1, 16 DP-2, 17 HDMI-1, 18 HDMI-2, 27 USB-C), mais certains fabricants s'en écartent : un Dell U2725QE utilise 25 pour l'USB-C.",
        shortcutRow: "Raccourci {0}",
        enabled: "Activé",
        name: "Nom",
        namePrompt: "p. ex. PC Windows",
        targetInput: "Entrée cible",
        shortcut: "Raccourci",
        recordShortcut: "Enregistrer le raccourci",
        typeShortcut: "Tapez le raccourci…",
        clearShortcut: "Effacer le raccourci",
        shortcutsFooter: "Les raccourcis fonctionnent dans toutes les apps tant que DdcSwitch est ouvert. Appuyez sur Échap pour annuler l'enregistrement.",
        errRowInput: "« {0} » n'est pas une entrée valide. Saisissez un nombre, par exemple 17.",
        errRowNoHotkey: "Enregistrez un raccourci ou désactivez cette ligne.",
        errRowModifier: "Le raccourci doit comporter au moins une des touches ⌃ ⌥ ⇧ ⌘.",
        errRowDuplicate: "{0} est utilisé par plusieurs lignes.",
        switchTo: "Basculer vers",
        beforeShutdown: "Avant l'extinction",
        skipOnRestart: "Pas lors d'un redémarrage",
        beforeSleep: "Avant la mise en veille",
        powerFooter: "DdcSwitch bascule l'entrée lorsque macOS quitte les apps pour s'éteindre. Les redémarrages et les déconnexions sont reconnus ; une déconnexion ne bascule jamais.",
        errShutdownInput: "« {0} » n'est pas une entrée valide.",
        notRunningAtLogin: "DdcSwitch ne s'ouvre pas à la connexion : il ne peut basculer que s'il est ouvert.",
        turnOnLaunchAtLogin: "Activer"
    )

    static let de = Strings(
        langName: "Deutsch",
        appTagline: "DdcSwitch – Monitoreingang umschalten",
        menuSwitchTo: "Auf {0} umschalten",
        menuNoHotkeys: "Keine Kurzbefehle eingerichtet",
        menuShutdownSwitch: "Vor dem Ausschalten auf {0} umschalten",
        menuLaunchAtLogin: "Bei der Anmeldung öffnen",
        menuSettings: "Einstellungen …",
        menuOpenLog: "Protokoll öffnen",
        menuQuit: "DdcSwitch beenden",
        menuAbout: "Über DdcSwitch",
        aboutDescription: "Schaltet den Eingang des Monitors per DDC/CI um – per Kurzbefehl oder kurz bevor der Mac ausgeschaltet wird.",
        switchedTitle: "Eingang umgeschaltet",
        switchFailedTitle: "Eingang konnte nicht umgeschaltet werden",
        hotkeysFailedTitle: "Einige Kurzbefehle konnten nicht registriert werden",
        hotkeyInUse: "{0} wird bereits von einer anderen App verwendet.",
        launchAtLoginFailed: "„Bei der Anmeldung öffnen“ konnte nicht geändert werden: {0}",
        saveFailed: "Einstellungen konnten nicht gespeichert werden: {0}",
        errMonitorNotFound: "Monitor Nr. {0} nicht gefunden ({1} DDC/CI-Monitor(e) erkannt)",
        errSetFailed: "{0}: Umschalten des Eingangs fehlgeschlagen (Fehler {1})",
        errReadFailed: "{0}: Lesen des Eingangs fehlgeschlagen (Fehler {1})",
        errCapsFailed: "{0}: Fähigkeiten konnten nicht gelesen werden (ist DDC/CI im Monitormenü aktiviert?)",
        paneGeneral: "Allgemein",
        paneMonitor: "Monitor",
        paneShortcuts: "Kurzbefehle",
        panePower: "Ausschalten & Ruhezustand",
        launchAtLogin: "Bei der Anmeldung öffnen",
        launchAtLoginFooter: "DdcSwitch muss laufen, um vor dem Ausschalten oder dem Ruhezustand umzuschalten.",
        loginNeedsApproval: "Muss in den Systemeinstellungen erlaubt werden.",
        openLoginItems: "Anmeldeobjekte öffnen …",
        notifySuccess: "Nach jedem Umschalten benachrichtigen",
        notifyFooter: "Fehler werden immer angezeigt.",
        language: "Sprache",
        langAuto: "Systemsprache",
        appearance: "Erscheinungsbild",
        appearanceAuto: "System",
        appearanceLight: "Hell",
        appearanceDark: "Dunkel",
        log: "Protokoll",
        openLog: "Protokoll öffnen",
        configFile: "Einstellungsdatei",
        showInFinder: "Im Finder zeigen",
        version: "Version {0}",
        monitor: "Monitor",
        noMonitors: "Kein DDC/CI-Monitor erkannt",
        detectAgain: "Neu erkennen",
        currentInput: "Aktueller Eingang",
        reportedInputs: "Gemeldete Eingänge",
        reading: "Wird gelesen …",
        notReported: "Nicht gemeldet",
        monitorFooter: "Die Codes folgen dem VESA-MCCS-Standard (15 DP-1, 16 DP-2, 17 HDMI-1, 18 HDMI-2, 27 USB-C), manche Hersteller weichen ab: Ein Dell U2725QE verwendet 25 für USB-C.",
        shortcutRow: "Kurzbefehl {0}",
        enabled: "Aktiviert",
        name: "Name",
        namePrompt: "z. B. Windows-PC",
        targetInput: "Zieleingang",
        shortcut: "Kurzbefehl",
        recordShortcut: "Kurzbefehl aufnehmen",
        typeShortcut: "Kurzbefehl drücken …",
        clearShortcut: "Kurzbefehl löschen",
        shortcutsFooter: "Kurzbefehle funktionieren in allen Apps, solange DdcSwitch läuft. Mit Esc brichst du die Aufnahme ab.",
        errRowInput: "„{0}“ ist kein gültiger Eingang. Gib eine Zahl wie 17 ein.",
        errRowNoHotkey: "Nimm einen Kurzbefehl auf oder deaktiviere diese Zeile.",
        errRowModifier: "Der Kurzbefehl braucht mindestens eine der Tasten ⌃ ⌥ ⇧ ⌘.",
        errRowDuplicate: "{0} wird in mehreren Zeilen verwendet.",
        switchTo: "Umschalten auf",
        beforeShutdown: "Vor dem Ausschalten",
        skipOnRestart: "Nicht beim Neustart",
        beforeSleep: "Vor dem Ruhezustand",
        powerFooter: "DdcSwitch schaltet um, wenn macOS zum Ausschalten die Apps beendet. Neustarts und Abmeldungen werden erkannt; beim Abmelden wird nie umgeschaltet.",
        errShutdownInput: "„{0}“ ist kein gültiger Eingang.",
        notRunningAtLogin: "DdcSwitch wird bei der Anmeldung nicht geöffnet und kann daher nur umschalten, solange es läuft.",
        turnOnLaunchAtLogin: "Aktivieren"
    )

    static let ptBR = Strings(
        langName: "Português (Brasil)",
        appTagline: "DdcSwitch – troca a entrada do monitor",
        menuSwitchTo: "Mudar para {0}",
        menuNoHotkeys: "Nenhum atalho configurado",
        menuShutdownSwitch: "Mudar para {0} antes de desligar",
        menuLaunchAtLogin: "Abrir ao iniciar sessão",
        menuSettings: "Ajustes…",
        menuOpenLog: "Abrir registro",
        menuQuit: "Encerrar DdcSwitch",
        menuAbout: "Sobre o DdcSwitch",
        aboutDescription: "Troca a entrada do monitor via DDC/CI – com um atalho de teclado ou logo antes de o Mac desligar.",
        switchedTitle: "Entrada trocada",
        switchFailedTitle: "Não foi possível trocar a entrada",
        hotkeysFailedTitle: "Alguns atalhos não puderam ser registrados",
        hotkeyInUse: "{0} já está sendo usado por outro app.",
        launchAtLoginFailed: "Não foi possível alterar \"Abrir ao iniciar sessão\": {0}",
        saveFailed: "Não foi possível salvar os ajustes: {0}",
        errMonitorNotFound: "Monitor nº {0} não encontrado ({1} monitor(es) DDC/CI detectado(s))",
        errSetFailed: "{0}: falha ao trocar a entrada (erro {1})",
        errReadFailed: "{0}: falha ao ler a entrada (erro {1})",
        errCapsFailed: "{0}: não foi possível ler os recursos (o DDC/CI está ativado no menu do monitor?)",
        paneGeneral: "Geral",
        paneMonitor: "Monitor",
        paneShortcuts: "Atalhos",
        panePower: "Desligar e repouso",
        launchAtLogin: "Abrir ao iniciar sessão",
        launchAtLoginFooter: "O DdcSwitch precisa estar aberto para trocar antes de desligar ou entrar em repouso.",
        loginNeedsApproval: "Requer sua aprovação nos Ajustes do Sistema.",
        openLoginItems: "Abrir Itens de Início…",
        notifySuccess: "Notificar a cada troca",
        notifyFooter: "Falhas são sempre notificadas.",
        language: "Idioma",
        langAuto: "Idioma do sistema",
        appearance: "Aparência",
        appearanceAuto: "Sistema",
        appearanceLight: "Clara",
        appearanceDark: "Escura",
        log: "Registro",
        openLog: "Abrir registro",
        configFile: "Arquivo de ajustes",
        showInFinder: "Mostrar no Finder",
        version: "Versão {0}",
        monitor: "Monitor",
        noMonitors: "Nenhum monitor DDC/CI detectado",
        detectAgain: "Detectar novamente",
        currentInput: "Entrada atual",
        reportedInputs: "Entradas informadas",
        reading: "Lendo…",
        notReported: "Não informadas",
        monitorFooter: "Os códigos seguem o padrão VESA MCCS (15 DP-1, 16 DP-2, 17 HDMI-1, 18 HDMI-2, 27 USB-C), mas há fabricantes que usam outros: um Dell U2725QE usa 25 para USB-C.",
        shortcutRow: "Atalho {0}",
        enabled: "Ativado",
        name: "Nome",
        namePrompt: "ex.: PC com Windows",
        targetInput: "Entrada de destino",
        shortcut: "Atalho",
        recordShortcut: "Gravar atalho",
        typeShortcut: "Digite o atalho…",
        clearShortcut: "Limpar atalho",
        shortcutsFooter: "Os atalhos funcionam em qualquer app enquanto o DdcSwitch estiver aberto. Pressione Esc para cancelar a gravação.",
        errRowInput: "\"{0}\" não é uma entrada válida. Digite um número, como 17.",
        errRowNoHotkey: "Grave um atalho ou desative esta linha.",
        errRowModifier: "O atalho precisa de pelo menos uma das teclas ⌃ ⌥ ⇧ ⌘.",
        errRowDuplicate: "{0} é usado em mais de uma linha.",
        switchTo: "Mudar para",
        beforeShutdown: "Antes de desligar",
        skipOnRestart: "Não ao reiniciar",
        beforeSleep: "Antes do repouso",
        powerFooter: "O DdcSwitch troca a entrada quando o macOS encerra os apps para desligar. Reinícios e saídas da sessão são reconhecidos; ao sair da sessão, nunca troca.",
        errShutdownInput: "\"{0}\" não é uma entrada válida.",
        notRunningAtLogin: "O DdcSwitch não abre ao iniciar sessão, então só pode trocar enquanto estiver aberto.",
        turnOnLaunchAtLogin: "Ativar"
    )

    static let ru = Strings(
        langName: "Русский",
        appTagline: "DdcSwitch — переключение входа монитора",
        menuSwitchTo: "Переключить на {0}",
        menuNoHotkeys: "Сочетания клавиш не настроены",
        menuShutdownSwitch: "Переключать на {0} перед выключением",
        menuLaunchAtLogin: "Открывать при входе",
        menuSettings: "Настройки…",
        menuOpenLog: "Открыть журнал",
        menuQuit: "Завершить DdcSwitch",
        menuAbout: "О программе DdcSwitch",
        aboutDescription: "Переключает вход монитора по DDC/CI — сочетанием клавиш или непосредственно перед выключением Mac.",
        switchedTitle: "Вход переключён",
        switchFailedTitle: "Не удалось переключить вход",
        hotkeysFailedTitle: "Не удалось зарегистрировать некоторые сочетания клавиш",
        hotkeyInUse: "{0} уже используется другим приложением.",
        launchAtLoginFailed: "Не удалось изменить «Открывать при входе»: {0}",
        saveFailed: "Не удалось сохранить настройки: {0}",
        errMonitorNotFound: "Монитор № {0} не найден (обнаружено мониторов DDC/CI: {1})",
        errSetFailed: "{0}: не удалось переключить вход (ошибка {1})",
        errReadFailed: "{0}: не удалось прочитать вход (ошибка {1})",
        errCapsFailed: "{0}: не удалось прочитать возможности (включён ли DDC/CI в меню монитора?)",
        paneGeneral: "Основные",
        paneMonitor: "Монитор",
        paneShortcuts: "Сочетания клавиш",
        panePower: "Выключение и сон",
        launchAtLogin: "Открывать при входе",
        launchAtLoginFooter: "Чтобы переключать вход перед выключением или сном, DdcSwitch должен быть запущен.",
        loginNeedsApproval: "Требуется разрешение в Системных настройках.",
        openLoginItems: "Открыть «Объекты входа»…",
        notifySuccess: "Уведомлять о каждом переключении",
        notifyFooter: "Об ошибках уведомляет всегда.",
        language: "Язык",
        langAuto: "Язык системы",
        appearance: "Оформление",
        appearanceAuto: "Как в системе",
        appearanceLight: "Светлое",
        appearanceDark: "Тёмное",
        log: "Журнал",
        openLog: "Открыть журнал",
        configFile: "Файл настроек",
        showInFinder: "Показать в Finder",
        version: "Версия {0}",
        monitor: "Монитор",
        noMonitors: "Мониторы DDC/CI не обнаружены",
        detectAgain: "Обнаружить снова",
        currentInput: "Текущий вход",
        reportedInputs: "Входы по данным монитора",
        reading: "Чтение…",
        notReported: "Не сообщаются",
        monitorFooter: "Коды входов определены стандартом VESA MCCS (15 DP-1, 16 DP-2, 17 HDMI-1, 18 HDMI-2, 27 USB-C), но производители отступают от него: Dell U2725QE использует 25 для USB-C.",
        shortcutRow: "Сочетание {0}",
        enabled: "Включено",
        name: "Название",
        namePrompt: "например, ПК с Windows",
        targetInput: "Целевой вход",
        shortcut: "Сочетание клавиш",
        recordShortcut: "Записать сочетание",
        typeShortcut: "Нажмите сочетание…",
        clearShortcut: "Очистить сочетание",
        shortcutsFooter: "Сочетания работают в любом приложении, пока запущен DdcSwitch. Чтобы отменить запись, нажмите Esc.",
        errRowInput: "«{0}» — недопустимый вход. Введите число, например 17.",
        errRowNoHotkey: "Запишите сочетание клавиш или выключите эту строку.",
        errRowModifier: "Сочетание должно включать хотя бы одну из клавиш ⌃ ⌥ ⇧ ⌘.",
        errRowDuplicate: "{0} используется в нескольких строках.",
        switchTo: "Переключать на",
        beforeShutdown: "Перед выключением",
        skipOnRestart: "Не при перезагрузке",
        beforeSleep: "Перед сном",
        powerFooter: "DdcSwitch переключает вход, когда macOS завершает приложения перед выключением. Перезагрузка и выход из системы распознаются; при выходе из системы вход не переключается.",
        errShutdownInput: "«{0}» — недопустимый вход.",
        notRunningAtLogin: "DdcSwitch не открывается при входе, поэтому переключает вход, только пока запущен.",
        turnOnLaunchAtLogin: "Включить"
    )
}
