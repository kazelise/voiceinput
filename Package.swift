// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            path: "Sources/VoiceInput",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
