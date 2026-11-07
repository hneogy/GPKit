// swift-tools-version: 6.0

import PackageDescription

// The propagation benchmark (conformance/benchmark-*.txt): a tool, not part of the library.
let package = Package(
    name: "benchmark",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "GPKit", path: "../..")],
    targets: [
        .executableTarget(name: "benchmark", dependencies: [.product(name: "GPKit", package: "GPKit")]),
    ]
)
