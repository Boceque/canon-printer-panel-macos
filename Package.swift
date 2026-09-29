// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YaziciPaneli",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "YaziciPaneli",
            path: "Kaynak",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
