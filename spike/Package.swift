// swift-tools-version:5.9
import Foundation
import PackageDescription

// Embed Info.plist into the binary so macOS has a usage string
// (NSAudioCaptureUsageDescription) to show in the permission prompt.
let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/audiotap/Info.plist")
    .path

let package = Package(
    name: "audiotap",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(
            name: "audiotap",
            path: "Sources/audiotap",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),
    ]
)
