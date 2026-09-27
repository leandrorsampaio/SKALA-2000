// swift-tools-version: 6.0
import PackageDescription

// The copied modules were written for language mode 5; they stay there until strict
// concurrency is worth a pass of its own.
let settings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "SKALA-2000",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SKALA-2000", targets: ["SKALA2000App"])
    ],
    targets: [
        // What Claude Code and the Mac report, as typed readings with a time-to-live.
        .target(name: "TelemetryKit", swiftSettings: settings),
        // The console's rules: readings and operator intents in, one value per instrument
        // out. No UI, no I/O.
        .target(name: "ConsoleKit", dependencies: ["TelemetryKit"], swiftSettings: settings),
        // A scripted day of telemetry, for tests and demo mode.
        .target(name: "FakeSources", dependencies: ["TelemetryKit"], swiftSettings: settings),
        // The console's edge with the world: its files, its timer, pmset, the F-keys.
        .target(
            name: "ConsoleRuntime", dependencies: ["ConsoleKit", "TelemetryKit"],
            swiftSettings: settings),
        // FC1 and FC2: IOKit power assertions.
        .target(name: "KeepAwake", swiftSettings: settings),
        // Claude Code hook events over a Unix domain socket, and the hook installer.
        .target(name: "HookServer", swiftSettings: settings),
        // The relays, the buzzer and the director that plays them from snapshots.
        .target(name: "DeskSound", dependencies: ["ConsoleKit", "DeskArt"], swiftSettings: settings),
        // Tokens, fonts, the layout table and the Core Graphics painters.
        .target(name: "DeskArt", dependencies: ["ConsoleKit"], swiftSettings: settings),
        // The layer tree that renders a snapshot, and takes the operator's input.
        .target(
            name: "DeskView", dependencies: ["DeskArt", "ConsoleKit"], swiftSettings: settings),
        .executableTarget(
            name: "SKALA2000App",
            dependencies: [
                "TelemetryKit", "ConsoleKit", "ConsoleRuntime", "FakeSources", "KeepAwake",
                "HookServer", "DeskSound", "DeskArt", "DeskView",
            ],
            swiftSettings: settings),

        // Development only, never shipped: the reference SwiftUI desk, tagged, which exports
        // the layout table and the golden renders. See Sources/DeskReference/main.swift.
        .executableTarget(
            name: "DeskReference",
            dependencies: ["ConsoleKit", "FakeSources", "TelemetryKit", "DeskArt", "DeskView"],
            swiftSettings: settings),

        .testTarget(name: "TelemetryKitTests", dependencies: ["TelemetryKit"], swiftSettings: settings),
        .testTarget(
            name: "ConsoleKitTests",
            dependencies: ["ConsoleKit", "TelemetryKit", "FakeSources", "HookServer"],
            swiftSettings: settings),
        .testTarget(
            name: "ConsoleRuntimeTests",
            dependencies: ["ConsoleRuntime", "ConsoleKit", "TelemetryKit"],
            swiftSettings: settings),
        .testTarget(
            name: "DeskTests",
            dependencies: [
                "DeskArt", "DeskView", "DeskSound", "ConsoleKit", "FakeSources", "TelemetryKit",
                "KeepAwake", "HookServer",
            ],
            // Read from the source tree by path, not bundled.
            exclude: ["Goldens"],
            swiftSettings: settings),
    ]
)
