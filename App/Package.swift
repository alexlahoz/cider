// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Cider",
    defaultLocalization: "es",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cider",
            path: "Sources/Cider",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        )
    ]
)
