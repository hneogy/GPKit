// swift-tools-version: 6.0
// The bit record (GPKit 2.1): the release build's propagate outputs held to a recorded set at the bit, per platform.
// A package of its own, so GPKit's own package gains no product.
import PackageDescription

let package = Package(
    name: "gpkit-bit-record",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "GPKit", path: "../..")],
    targets: [
        .executableTarget(name: "gpkit-bit-record", dependencies: [.product(name: "GPKit", package: "GPKit")]),
    ]
)
