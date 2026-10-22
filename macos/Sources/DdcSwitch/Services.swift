// Small system services: the log file, launch at login, notifications, global hotkeys and
// the sleep notification.

import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt
import ServiceManagement
import UserNotifications

// ---------------------------------------------------------------------------
// Log: append-only, flushed on every line so entries written during shutdown survive.

enum AppLog {
    private static let maxSize: UInt64 = 512 * 1024
    private static let queue = DispatchQueue(label: "DdcSwitch.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.sync {
            let url = Paths.logFile
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size > maxSize {
                let old = url.deletingPathExtension().appendingPathExtension("old.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.synchronize()
        }
    }
}

// ---------------------------------------------------------------------------
// Launch at login via SMAppService (shown in System Settings › General › Login Items).

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) throws {
        if on {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

// ---------------------------------------------------------------------------
// Notifications (Notification Center banners).

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var authorized: Bool?

    /// UNUserNotificationCenter only works inside an app bundle.
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func post(_ title: String, _ body: String) {
        guard available else {
            FileHandle.standardError.write(Data("\(title): \(body)\n".utf8))
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if authorized == true { return send() }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.authorized = granted
                if granted { send() } else { AppLog.log("Notifications are not allowed: \(title): \(body)") }
            }
        }
    }

    // Show banners even while the settings window is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

// ---------------------------------------------------------------------------
// Global hotkeys via Carbon's RegisterEventHotKey: no Accessibility permission needed.

final class HotkeyCenter {
    var onPress: ((Int) -> Void)?
    private var refs: [Int: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4464_6353 // 'DdcS'

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, user in
            guard let event, let user else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(user).takeUnretainedValue()
            center.onPress?(Int(id.id))
            return noErr
        }, 1, &spec, me, &handler)
    }

    /// Registers the bindings that are enabled and valid; returns the slots (0-based) that another app already owns.
    @discardableResult
    func register(_ bindings: [HotkeyBinding], skipping invalid: Set<Int> = []) -> [Int] {
        unregisterAll()
        var failed: [Int] = []
        for (i, b) in bindings.enumerated() where b.enabled && !invalid.contains(i) {
            guard let key = b.key else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: HotkeyCenter.signature, id: UInt32(i + 1))
            let status = RegisterEventHotKey(UInt32(key), b.mods.carbonFlags, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs[i] = ref
            } else {
                AppLog.log("Could not register hotkey \(hotkeyToString(b.mods, b.key)) (status \(status))")
                failed.append(i)
            }
        }
        return failed
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }
}

// ---------------------------------------------------------------------------
// Sleep: IOKit power notifications let us finish switching before the system sleeps.

final class PowerMonitor {
    var onWillSleep: (() -> Void)?
    private var root: io_connect_t = 0
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0

    func start() {
        let me = Unmanaged.passUnretained(self).toOpaque()
        root = IORegisterForSystemPower(me, &port, { refcon, _, messageType, argument in
            guard let refcon else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(messageType, argument)
        }, &notifier)
        guard root != 0, let port else {
            AppLog.log("IORegisterForSystemPower failed")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
    }

    // iokit_common_msg(0x270) / (0x280): the C macros are not imported into Swift.
    private static let canSystemSleep: natural_t = 0xE000_0270
    private static let systemWillSleep: natural_t = 0xE000_0280

    private func handle(_ messageType: natural_t, _ argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case PowerMonitor.canSystemSleep:
            IOAllowPowerChange(root, Int(bitPattern: argument))
        case PowerMonitor.systemWillSleep:
            onWillSleep?()
            IOAllowPowerChange(root, Int(bitPattern: argument))
        default:
            break
        }
    }
}
