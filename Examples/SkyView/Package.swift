// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SkyView",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "GPKit", path: "../..")],
    targets: [
        .executableTarget(name: "SkyView", dependencies: [.product(name: "GPKit", package: "GPKit")]),
    ]
)
