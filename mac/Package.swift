// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iPodFirm",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "IPodFWKit"),
        .executableTarget(name: "iPodFirm", dependencies: ["IPodFWKit"]),
        .executableTarget(name: "ipodfw-helper", dependencies: ["IPodFWKit"]),
        .testTarget(name: "IPodFWKitTests", dependencies: ["IPodFWKit"]),
    ],
    swiftLanguageModes: [.v5]
)
