// swift-tools-version: 6.0

import PackageDescription

// The OMM/TLE equivalence measurement (conformance/omm-tle-equivalence-*.txt): a tool, not part of the library.
let package = Package(
    name: "equivalence",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "GPKit", path: "../..")],
    targets: [
        .executableTarget(name: "equivalence", dependencies: [.product(name: "GPKit", package: "GPKit")]),
    ]
)
