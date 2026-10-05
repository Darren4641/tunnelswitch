// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TunnelSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TunnelSwitch", path: "Sources/TunnelSwitch"),
    ]
)
