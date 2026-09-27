// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wingman",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WingmanCore"),
        .executableTarget(name: "Wingman", dependencies: ["WingmanCore"]),
        .testTarget(name: "WingmanCoreTests", dependencies: ["WingmanCore"]),
    ],
    swiftLanguageModes: [.v5]
)
