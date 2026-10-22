// The menu bar app: status item and menu, hotkeys, and switching before shutdown and sleep.

import AppKit

/// Four-character codes of the Apple events macOS sends when it quits apps.
private func fourCC(_ s: String) -> OSType { s.utf8.reduce(0) { $0 << 8 | OSType($1) } }
private let aeQuitReason = fourCC("why?")
private let aeShutDown = fourCC("shut")
private let aeShowShutdownDialog = fourCC("rsdn")
private let aeRestart = fourCC("rest")
private let aeShowRestartDialog = fourCC("rrst")
private let aeReallyLogOut = fourCC("rlgo")
private let aeLogOut = fourCC("logo")

enum AppIdentity {
    static let bundleID = "io.github.pokoblin.DdcSwitch"
    static let showSettings = Notification.Name("io.github.pokoblin.DdcSwitch.showSettings")
    static let quit = Notification.Name("io.github.pokoblin.DdcSwitch.quit")
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static let repository = URL(string: "https://github.com/pokoblin/DdcSwitch")!
}

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var cfg: Config
    private let firstRun: Bool
    let hotkeys = HotkeyCenter()
    private let power = PowerMonitor()
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController?
    private(set) lazy var settingsModel = SettingsModel(app: self)
    private var invalidRows: Set<Int> = []

    init(config: Config, firstRun: Bool) {
        cfg = config
        self.firstRun = firstRun
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Without these macOS may kill the app at shutdown without sending it a quit event.
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("Switches the monitor input before shutdown")

        NSApp.mainMenu = makeMainMenu()
        applyAppearance(cfg.appearance)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.image
        statusItem.button?.setAccessibilityLabel("DdcSwitch")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateTooltip()

        hotkeys.onPress = { [weak self] slot in
            guard let self, let b = self.cfg.bindings[safe: slot - 1] else { return }
            self.switchAsync(to: b.input, source: "hotkey")
        }
        let failures = registerHotkeys()
        power.onWillSleep = { [weak self] in self?.onWillSleep() }
        power.start()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            AppLog.log("NSWorkspaceWillPowerOff: macOS is logging out, restarting or shutting down")
        }
        let dist = DistributedNotificationCenter.default()
        dist.addObserver(forName: AppIdentity.showSettings, object: nil, queue: .main) { [weak self] _ in self?.openSettings() }
        dist.addObserver(forName: AppIdentity.quit, object: nil, queue: .main) { _ in NSApp.terminate(nil) }

        AppLog.log("Started v\(AppIdentity.version), config: \(Paths.configFile.path), switch at shutdown: "
            + (cfg.shutdownSwitch ? cfg.inputTitle(cfg.shutdownInput) : "off"))
        if !failures.isEmpty {
            let lines = failures.map { I18n.fmt(I18n.t.hotkeyInUse, hotkeyDisplay(cfg.bindings[$0].mods, cfg.bindings[$0].key)) }
            Notifier.shared.post(I18n.t.hotkeysFailedTitle, lines.joined(separator: "\n"))
        }
        if firstRun { openSettings(pane: .monitor) }
        #if DEBUG
        if let dir = DebugSnapshot.directory { DebugSnapshot.run(self, into: dir) }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == fourCC("aevt"), event.eventID == fourCC("quit") else {
            return .terminateNow // quit from the menu, `--quit` or a script
        }
        let descriptor = event.attributeDescriptor(forKeyword: aeQuitReason) ?? event.paramDescriptor(forKeyword: aeQuitReason)
        let reason = descriptor.map { $0.enumCodeValue != 0 ? $0.enumCodeValue : $0.typeCodeValue } ?? 0
        AppLog.log("Quit Apple event, reason '\(reason == 0 ? "none" : fourCCString(reason))'")
        switch reason {
        case aeShutDown, aeShowShutdownDialog:
            onShutdown(restart: false)
        case aeRestart, aeShowRestartDialog:
            onShutdown(restart: true)
        case aeReallyLogOut, aeLogOut:
            AppLog.log("    logging out, not a shutdown, skipped")
        default:
            break
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregisterAll()
        AppLog.log("Exit")
    }

    private func fourCCString(_ v: OSType) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xFF) }, encoding: .macOSRoman) ?? "\(v)"
    }

    // -----------------------------------------------------------------------
    // Switching

    func switchAsync(to input: UInt32, source: String) {
        let (index, name, title) = (cfg.monitor, cfg.monitorName, cfg.inputTitle(input))
        DispatchQueue.global(qos: .userInitiated).async {
            var message: String
            var ok = true
            do {
                message = "\(try DDC.setVCP(index: index, name: name, code: vcpInput, value: input)) → \(title)"
            } catch {
                ok = false
                message = "\(error)"
            }
            AppLog.log("[\(source)] switch to \(title): \(ok ? "ok" : "FAILED")")
            if !ok { AppLog.log("    \(message)") }
            DispatchQueue.main.async {
                if !ok {
                    Notifier.shared.post(I18n.t.switchFailedTitle, message)
                } else if self.cfg.notifySuccess {
                    Notifier.shared.post(I18n.t.switchedTitle, message)
                }
            }
        }
    }

    /// Synchronous switch used while the system is going down.
    private func switchNow(reason: String) {
        let title = cfg.inputTitle(cfg.shutdownInput)
        let started = Date()
        do {
            let mon = try DDC.setVCP(index: cfg.monitor, name: cfg.monitorName, code: vcpInput, value: cfg.shutdownInput)
            AppLog.log("[\(reason)] switched \(mon) → \(title) (\(Int(Date().timeIntervalSince(started) * 1000)) ms)")
        } catch {
            AppLog.log("[\(reason)] switch to \(title) FAILED: \(error)")
        }
    }

    private func onShutdown(restart: Bool) {
        guard cfg.shutdownSwitch else {
            AppLog.log("    switching at shutdown is off, skipped")
            return
        }
        if restart && cfg.skipOnRestart {
            AppLog.log("    this is a restart, input not switched")
            return
        }
        switchNow(reason: restart ? "restart" : "shutdown")
    }

    private func onWillSleep() {
        guard cfg.sleepSwitch else { return }
        AppLog.log("kIOMessageSystemWillSleep (going to sleep)")
        switchNow(reason: "sleep")
    }

    // -----------------------------------------------------------------------
    // Settings

    /// Rows (0-based) whose shortcut another app already owns.
    private(set) var hotkeyFailures: [Int] = []
    private var hotkeysSuspended = false

    @discardableResult
    private func registerHotkeys() -> [Int] {
        hotkeyFailures = hotkeys.register(cfg.bindings, skipping: invalidRows)
        return hotkeyFailures
    }

    /// Called by the settings window whenever something changed. Returns an error if the file could not be saved.
    func apply(_ new: Config, invalidRows: Set<Int>) -> String? {
        var saveError: String?
        if new != cfg {
            do { try new.save() } catch { saveError = I18n.fmt(I18n.t.saveFailed, error.localizedDescription) }
        }
        if new.language != cfg.language { I18n.apply(new.language) }
        if new.appearance != cfg.appearance { applyAppearance(new.appearance) }
        let hotkeysChanged = new.bindings != cfg.bindings || invalidRows != self.invalidRows
        cfg = new
        self.invalidRows = invalidRows
        updateTooltip()
        if hotkeysChanged && !hotkeysSuspended { registerHotkeys() }
        return saveError
    }

    /// While a shortcut is being recorded the registered ones must not swallow the keys.
    /// "auto" follows the system; "light" and "dark" fix the look of the settings window and menu.
    private func applyAppearance(_ setting: String) {
        switch setting {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func setHotkeysSuspended(_ on: Bool) {
        guard on != hotkeysSuspended else { return }
        hotkeysSuspended = on
        if on { hotkeys.unregisterAll() } else { registerHotkeys() }
    }

    func openSettings(pane: SettingsModel.Pane? = nil) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(model: settingsModel)
        }
        settingsModel.reload(from: cfg)
        if let pane { settingsModel.pane = pane }
        settingsWindow?.show()
    }

    // -----------------------------------------------------------------------
    // Status item & menu

    private func updateTooltip() {
        var tip = I18n.t.appTagline
        for b in cfg.bindings where b.enabled && b.key != nil {
            tip += "\n\(hotkeyDisplay(b.mods, b.key)) → \(cfg.inputTitle(b.input))"
        }
        statusItem?.button?.toolTip = tip
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let t = I18n.t
        menu.removeAllItems()
        var any = false
        for (i, b) in cfg.bindings.enumerated() where b.enabled {
            any = true
            let item = NSMenuItem(title: I18n.fmt(t.menuSwitchTo, cfg.inputTitle(b.input)), action: #selector(menuSwitch(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            if let key = b.key, let info = KeyCode.info(key), !invalidRows.contains(i) {
                item.keyEquivalent = info.equivalent
                item.keyEquivalentModifierMask = b.mods.eventFlags
            }
            menu.addItem(item)
        }
        if !any {
            let item = NSMenuItem(title: t.menuNoHotkeys, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let shutdown = NSMenuItem(title: I18n.fmt(t.menuShutdownSwitch, cfg.inputTitle(cfg.shutdownInput)),
                                  action: #selector(toggleShutdown), keyEquivalent: "")
        shutdown.target = self
        shutdown.state = cfg.shutdownSwitch ? .on : .off
        menu.addItem(shutdown)
        let login = NSMenuItem(title: t.menuLaunchAtLogin, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : (LaunchAtLogin.needsApproval ? .mixed : .off)
        menu.addItem(login)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: t.menuSettings, action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let log = NSMenuItem(title: t.menuOpenLog, action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        menu.addItem(.separator())
        let about = NSMenuItem(title: t.menuAbout, action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: t.menuQuit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func menuSwitch(_ sender: NSMenuItem) {
        guard let b = cfg.bindings[safe: sender.tag] else { return }
        switchAsync(to: b.input, source: "menu")
    }

    @objc private func toggleShutdown() {
        var new = cfg
        new.shutdownSwitch.toggle()
        if let error = apply(new, invalidRows: invalidRows) { Notifier.shared.post("DdcSwitch", error) }
        settingsModel.reload(from: cfg)
        AppLog.log("Settings updated")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        } catch {
            Notifier.shared.post(I18n.t.menuLaunchAtLogin, I18n.fmt(I18n.t.launchAtLoginFailed, error.localizedDescription))
        }
        if LaunchAtLogin.needsApproval { LaunchAtLogin.openSystemSettings() }
        settingsModel.refreshLaunchAtLogin()
    }

    @objc private func menuAbout() {
        DispatchQueue.main.async { self.showAbout() }
    }

    /// The standard About panel: icon, name and version, plus a description and a link to the repository.
    @objc func showAbout() {
        let t = I18n.t
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString(string: t.aboutDescription + "\n\n", attributes: [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centered,
        ])
        credits.append(NSAttributedString(string: "github.com/pokoblin/DdcSwitch", attributes: [
            .font: font, .link: AppIdentity.repository, .paragraphStyle: centered,
        ]))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "DdcSwitch",
            // Shown as is, so it carries the "Version" word in the app's own language.
            .applicationVersion: I18n.fmt(t.version, AppIdentity.version),
            .version: "",
            .credits: credits,
        ])
        // Like the settings window: a menu bar app has to push its panel to the front itself.
        NSApp.windows.first { $0 is NSPanel && $0.isVisible }?.orderFrontRegardless()
    }

    @objc private func menuSettings() {
        // Wait until the menu has closed: activating while it still tracks the mouse is undone when it closes.
        DispatchQueue.main.async { self.openSettings() }
    }

    @objc func openLog() {
        if !FileManager.default.fileExists(atPath: Paths.logFile.path) { AppLog.log("Log created") }
        NSWorkspace.shared.open(Paths.logFile)
    }

    /// Hidden main menu: gives the settings window the standard editing and window shortcuts.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        submenu("DdcSwitch", [
            NSMenuItem(title: "About DdcSwitch", action: #selector(showAbout), keyEquivalent: ""),
            item("Quit DdcSwitch", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        return main
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// The menu bar icon: a monitor with a ⇄ double arrow, drawn as a template image.
enum StatusIcon {
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let screen = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 2.25, width: 14.5, height: 10.5), xRadius: 2, yRadius: 2)
            screen.lineWidth = 1.5
            screen.stroke()
            NSBezierPath(rect: NSRect(x: 8.25, y: 12.75, width: 1.5, height: 2.25)).fill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: 14.5, width: 8, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            // ⇄ arrows inside the screen
            func arrow(from x0: CGFloat, to x1: CGFloat, y: CGFloat) {
                let dir: CGFloat = x1 > x0 ? 1 : -1
                let shaft = NSBezierPath()
                shaft.move(to: NSPoint(x: x0, y: y))
                shaft.line(to: NSPoint(x: x1 - dir * 1.6, y: y))
                shaft.lineWidth = 1.2
                shaft.stroke()
                let head = NSBezierPath()
                head.move(to: NSPoint(x: x1, y: y))
                head.line(to: NSPoint(x: x1 - dir * 2.4, y: y - 1.9))
                head.line(to: NSPoint(x: x1 - dir * 2.4, y: y + 1.9))
                head.close()
                head.fill()
            }
            arrow(from: 5, to: 13, y: 5.6)
            arrow(from: 13, to: 5, y: 9.4)
            return true
        }
        img.isTemplate = true
        return img
    }()
}
