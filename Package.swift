// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "zShot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ZShotCore"),
        .testTarget(name: "ZShotCoreTests", dependencies: ["ZShotCore"]),
    ],
    swiftLanguageModes: [.v5]
)
