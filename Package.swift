// swift-tools-version:5.9
import Foundation
import PackageDescription

// Embed an Info.plist into the audiotap CLI so macOS has a usage string
// (NSAudioCaptureUsageDescription) to show in the permission prompt.
let cliInfoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/audiotap/Info.plist")
    .path

let package = Package(
    name: "MacAudioPanel",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "MacAudioPanel", targets: ["MacAudioPanel"]),
        .executable(name: "audiotap", targets: ["audiotap"]),
    ],
    targets: [
        // Core Audio process listing and per-app muting. No UI.
        .target(name: "AudioCore"),

        // The menu-bar app. Packaged into an .app by scripts/build-app.sh.
        .executableTarget(
            name: "MacAudioPanel",
            dependencies: ["AudioCore"]
        ),

        // Command-line tool from the M0 spike, kept for debugging.
        .executableTarget(
            name: "audiotap",
            dependencies: ["AudioCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", cliInfoPlist,
                ]),
            ]
        ),
    ]
)
