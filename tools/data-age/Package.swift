// swift-tools-version: 6.0
// The data-age measurement (GPKit 2.0-c): a package of its own, so GPKit's own package gains no product.
import PackageDescription

let package = Package(
    name: "gpkit-data-age",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "GPKit", path: "../..")],
    targets: [
        .executableTarget(name: "gpkit-data-age", dependencies: [.product(name: "GPKit", package: "GPKit")]),
    ]
)
