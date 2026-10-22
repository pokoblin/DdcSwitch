// Small command line interface, mostly for diagnostics:
//   DdcSwitch --list | --get | --set <input> | --caps | --quit  [--monitor N]

import AppKit

enum CLI {
    static let usage = """
    DdcSwitch - switch the monitor input source over DDC/CI

    Without arguments DdcSwitch runs in the menu bar. Diagnostic commands:
      --list            list monitors
      --get             read the current input source
      --set <input>     switch input (number, 0x hex, or an alias such as hdmi1/dp1/usbc)
      --caps            read the capabilities string and supported inputs
      --quit            ask the running menu bar app to quit
      --monitor <N>     monitor number (default: the one in the config file)
      --config <path>   use another config file
    """

    static func run(_ args: [String]) -> Int32 {
        let (cfg, _) = Config.load()
        I18n.apply(cfg.language)
        var monitor = cfg.monitor
        var monitorName = cfg.monitorName
        var command: (name: String, value: String?)?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--monitor", "-d":
                monitor = args[safe: i + 1].flatMap { Int($0) } ?? 1
                monitorName = ""
                i += 1
            case "--set":
                command = ("set", args[safe: i + 1])
                i += 1
            case "--list", "--get", "--caps", "--quit":
                command = (String(args[i].dropFirst(2)), nil)
            case "--detect":
                command = ("detect", nil)
            default:
                command = ("help", nil)
            }
            i += 1
        }

        do {
            switch (command?.name, command?.value) {
            case ("list", _):
                let names = DDC.listNames()
                print("\(names.count) DDC/CI monitor(s) detected:")
                for (n, name) in names.enumerated() { print("  \(n + 1): \(name)") }
            case ("get", _):
                print("Current input: \(inputLabel(try DDC.getInput(index: monitor, name: monitorName)))")
            case ("set", let v?):
                guard let input = parseInput(v) else { throw DDCError(description: "Invalid input source: \(v)") }
                let m = try DDC.setVCP(index: monitor, name: monitorName, code: vcpInput, value: input)
                print("\(m) → \(inputLabel(input))")
            case ("caps", _):
                let caps = try DDC.capabilities(index: monitor, name: monitorName)
                print("\(caps)\n")
                print("Supported inputs (VCP 0x60):")
                for v in DDC.parseInputCaps(caps) { print("  \(inputLabel(v))") }
            case ("detect", _):
                print("Not needed on macOS: the quit event macOS sends at shutdown says whether it is a restart.")
            case ("quit", _):
                quitRunning()
            default:
                print(usage)
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            return 1
        }
    }

    static func runningInstances() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// Asks a running menu bar instance to quit and waits for it.
    private static func quitRunning() {
        guard !runningInstances().isEmpty else {
            print("DdcSwitch is not running")
            return
        }
        DistributedNotificationCenter.default().postNotificationName(AppIdentity.quit, object: nil, userInfo: nil, deliverImmediately: true)
        for _ in 0..<50 {
            if runningInstances().isEmpty {
                print("Exited")
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        print("Timed out waiting for DdcSwitch to exit")
    }
}
