// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GPKit",
    // The first release of each platform with Swift's Duration, which the pass search takes.
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "GPKit", targets: ["GPKit"]),
    ],
    targets: [
        // The library: Swift only, no dependency. One file, Date.swift, bridges to Foundation's Date where there is a
        // Foundation; the rest builds without it (tools/check-no-foundation.sh).
        .target(name: "GPKit"),
        // The gpconf command adapter (docs/ADAPTERS.md of gp-omm-conformance). Not a product: it exists for the
        // conformance run in CI and on a developer's machine.
        .executableTarget(name: "gpkit-gpconf", dependencies: ["GPKit"], path: "Sources/gpconf-adapter"),
        // Tests only: David Vallado's SGP4.cpp, compiled as it is, for GPKit's SGP4 to be compared with.
        .target(name: "SGP4Oracle", path: "Tests/SGP4Oracle", exclude: ["vallado"]),
        .testTarget(name: "GPKitTests", dependencies: ["GPKit", "SGP4Oracle"], resources: [.copy("Resources")]),
    ],
    cxxLanguageStandard: .cxx17
)
