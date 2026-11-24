// swift-tools-version: 5.9
// Host-side (macOS) unit tests for the watch app's pure logic.
//
// The Xcode project builds the watch app; this package only compiles the
// Foundation-only logic files straight from the app folder so `swift test`
// can run them with code coverage (see Makefile `test` / `coverage`).
// It is not a dependency of the app and adds no third-party packages.
import PackageDescription

let appFolder = "FallGuardian/FallGuardian Watch App"

let package = Package(
    name: "FallGuardianWatchLogic",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "FallGuardianWatchLogic",
            path: appFolder,
            exclude: [
                "Assets.xcassets",
                "ContentView.swift",
                "FallDetectionManager.swift",
                "FallGuardian Watch App.entitlements",
                "FallGuardianApp.swift",
                "InfoPlist.xcstrings",
                "Localizable.xcstrings",
                "WatchSessionManager.swift",
            ],
            sources: [
                "FallAlgorithm.swift",
                "WatchAlertDeadline.swift",
            ]
        ),
        .testTarget(
            name: "FallGuardianWatchLogicTests",
            dependencies: ["FallGuardianWatchLogic"],
            path: "FallGuardianTests"
        ),
    ]
)
