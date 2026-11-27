// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "zShot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "zShot", targets: ["zShot"]),
    ],
    targets: [
        .target(name: "ZShotCore"),
        .executableTarget(name: "zShot", dependencies: ["ZShotCore"]),
        .testTarget(name: "ZShotCoreTests", dependencies: ["ZShotCore"]),
    ],
    swiftLanguageModes: [.v5]
)
