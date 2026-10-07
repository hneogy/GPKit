// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GPKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "GPKit", targets: ["GPKit"]),
    ],
    targets: [
        // The library: Swift only, no dependency, no Foundation.
        .target(name: "GPKit"),
        // The gpconf command adapter (docs/ADAPTERS.md of gp-omm-conformance). Not a product: it exists for the
        // conformance run in CI and on a developer's machine.
        .executableTarget(name: "gpkit-gpconf", dependencies: ["GPKit"], path: "Sources/gpconf-adapter"),
        .testTarget(name: "GPKitTests", dependencies: ["GPKit"]),
    ]
)
