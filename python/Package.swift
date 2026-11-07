// swift-tools-version: 6.0

import PackageDescription

// pygpkit's native part: GPKit behind a C function that takes and gives JSON, built as the shared library the Python
// package loads, and the tool that writes GPKit's own answers for the Python tests to be held to.
let package = Package(
    name: "pygpkit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "pygpkit_core", type: .dynamic, targets: ["PyGPKitCore"]),
        .executable(name: "pygpkit-reference", targets: ["pygpkit-reference"]),
    ],
    dependencies: [.package(name: "GPKit", path: "..")],
    targets: [
        // GPKit's values written as JSON, the same way for the library and for the reference
        .target(name: "PyGPKitShared", dependencies: [.product(name: "GPKit", package: "GPKit")]),
        .target(name: "PyGPKitCore", dependencies: ["PyGPKitShared", .product(name: "GPKit", package: "GPKit")]),
        .executableTarget(name: "pygpkit-reference", dependencies: ["PyGPKitShared", .product(name: "GPKit", package: "GPKit")]),
    ]
)
