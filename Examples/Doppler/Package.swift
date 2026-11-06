// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Doppler",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "GPKit", path: "../..")],
    targets: [
        .executableTarget(name: "doppler", dependencies: [.product(name: "GPKit", package: "GPKit")]),
    ]
)
