// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PassPredictor",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "GPKit", path: "../..")],
    targets: [
        .executableTarget(name: "pass-predictor", dependencies: [.product(name: "GPKit", package: "GPKit")]),
    ]
)
