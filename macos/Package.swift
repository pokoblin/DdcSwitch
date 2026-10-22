// swift-tools-version:5.9
// The macOS version of DdcSwitch. The Windows version (Rust, repository root) is not affected by
// anything in this folder. Build the app bundle with `./build.sh`, run the tests with `swift test`.

import PackageDescription

let package = Package(
    name: "DdcSwitch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DdcSwitch",
            path: "Sources/DdcSwitch",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        // Draws the app icon (build.sh turns the PNGs into AppIcon.icns).
        .executableTarget(name: "IconGen", path: "Sources/IconGen"),
        .testTarget(name: "DdcSwitchTests", dependencies: ["DdcSwitch"], path: "Tests/DdcSwitchTests"),
    ]
)
