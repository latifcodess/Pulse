// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Pulse")
    ],
    swiftLanguageModes: [.v6]
)
