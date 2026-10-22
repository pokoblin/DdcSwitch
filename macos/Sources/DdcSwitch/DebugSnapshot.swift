// Debug builds only: `DDCSWITCH_SNAPSHOT=<dir> DdcSwitch` renders every settings pane to PNG
// (optionally in the languages listed in DDCSWITCH_SNAPSHOT_LANGS) and quits. Used to check layouts.

#if DEBUG
import AppKit

enum DebugSnapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["DDCSWITCH_SNAPSHOT"].map { URL(fileURLWithPath: $0) }
    }

    static func run(_ app: AppController, into dir: URL) {
        let langs = (ProcessInfo.processInfo.environment["DDCSWITCH_SNAPSHOT_LANGS"] ?? app.cfg.language)
            .split(separator: ",").map(String.init)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        switch ProcessInfo.processInfo.environment["DDCSWITCH_SNAPSHOT_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        let panes = (ProcessInfo.processInfo.environment["DDCSWITCH_SNAPSHOT_PANES"]?.split(separator: ",").compactMap { SettingsModel.Pane(rawValue: String($0)) })
            ?? SettingsModel.Pane.allCases
        var steps: [() -> Void] = []
        for lang in langs {
            for pane in panes {
                steps.append {
                    app.openSettings(pane: pane)
                    if app.settingsModel.language != lang { app.settingsModel.language = lang }
                    if let w = NSApp.windows.first(where: { $0.isVisible && $0.toolbar != nil }) {
                        print("opened \(Int(w.frame.width))x\(Int(w.frame.height))")
                    }
                }
                steps.append {
                    guard let window = NSApp.windows.first(where: { $0.isVisible && $0.toolbar != nil }),
                          let view = window.contentView?.superview,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let url = dir.appendingPathComponent("\(lang)-\(pane.rawValue).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    print("\(url.path) \(Int(window.frame.width))x\(Int(window.frame.height))")
                }
            }
        }
        if ProcessInfo.processInfo.environment["DDCSWITCH_SNAPSHOT_ISSUES"] != nil {
            // Problems shown inline: a duplicate shortcut, an invalid input, a recording in progress.
            let m = app.settingsModel
            for pane in [SettingsModel.Pane.shortcuts, .power] {
                steps.append {
                    app.openSettings(pane: pane)
                    m.rows[1].enabled = true
                    m.rows[1].mods = m.rows[0].mods
                    m.rows[1].key = m.rows[0].key
                    m.rows[2].enabled = true
                    m.rows[2].inputText = "hdmi9"
                    m.shutdownInputText = "abc"
                }
                steps.append {
                    guard let window = NSApp.windows.first(where: { $0.isVisible && $0.toolbar != nil }),
                          let view = window.contentView?.superview,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("issues-\(pane.rawValue).png"))
                }
            }
        }
        if ProcessInfo.processInfo.environment["DDCSWITCH_SNAPSHOT_ABOUT"] != nil {
            steps.append { app.showAbout() }
            steps.append {
                guard let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }),
                      let view = panel.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("about.png"))
                print("about \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
            }
        }
        steps.append { NSApp.terminate(nil) }
        func next(_ i: Int) {
            guard i < steps.count else { return }
            steps[i]()
            // Leave time for the monitor probe and the window resize animation.
            DispatchQueue.main.asyncAfter(deadline: .now() + (i == 0 ? 4 : 0.6)) { next(i + 1) }
        }
        next(0)
    }
}
#endif
