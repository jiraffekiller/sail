// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sail",
    platforms: [.macOS("26.0")],
    targets: [
        // Thin C wrapper around the AppleSMC user client (read-only: battery temperature).
        .target(
            name: "CSMC",
            path: "Sources/CSMC",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Objective-C bridge to the private PowerUI.framework (powerd manual charge limit).
        .target(
            name: "CPowerUI",
            path: "Sources/CPowerUI",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("Foundation")]
        ),
        // Pure logic shared by the app and the helper: policy state machine, XPC protocol, IDs.
        .target(name: "SailCore"),
        // Root launchd daemon: writes the charge limit into PowerUIAgent's preferences.
        .executableTarget(
            name: "SailHelper",
            dependencies: ["SailCore"],
            linkerSettings: [.linkedFramework("Foundation")]
        ),
        // Menu bar app.
        .executableTarget(
            name: "Sail",
            dependencies: ["SailCore", "CSMC", "CPowerUI"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(name: "SailCoreTests", dependencies: ["SailCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
