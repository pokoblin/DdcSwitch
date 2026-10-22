// DdcSwitch for macOS: a menu bar app that switches the monitor input source over DDC/CI,
// from global keyboard shortcuts and automatically right before the Mac shuts down or sleeps.

import AppKit

var configOverride: URL?
var rest: [String] = []
var argv = CommandLine.arguments.dropFirst().makeIterator()
while let a = argv.next() {
    if a == "--config" {
        configOverride = argv.next().map { URL(fileURLWithPath: $0) }
    } else if a.hasPrefix("-psn_") || a.hasPrefix("-NS") || a.hasPrefix("-Apple") {
        // Arguments added by LaunchServices or Xcode.
        _ = a.hasPrefix("-psn_") ? nil : argv.next()
    } else {
        rest.append(a)
    }
}
Paths.setConfigFile(configOverride)

if !rest.isEmpty {
    exit(CLI.run(rest))
}

// Single instance: a second launch just opens the settings of the running one.
if !CLI.runningInstances().isEmpty {
    DistributedNotificationCenter.default().postNotificationName(AppIdentity.showSettings, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

let (config, existed) = Config.load()
I18n.apply(config.language)
if !existed {
    do { try config.save() } catch { AppLog.log("Could not write \(Paths.configFile.path): \(error)") }
}

let app = NSApplication.shared
let controller = AppController(config: config, firstRun: !existed)
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
