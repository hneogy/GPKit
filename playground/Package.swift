// swift-tools-version: 6.0

import PackageDescription

// The playground of gpkit.gppasses.com (GPKit 2.0-b): GPKit compiled to WebAssembly as a WASI reactor, called by the
// page's script through a few exported functions, with no request of its own and no clock: the page passes the time
// in. A package of its own beside GPKit's, as pygpkit's is, so that its WebAssembly linker flags are never GPKit's.
//
// GPKit is built here from its own sources (Sources/GPKitCore is a link to ../Sources/GPKit) without Date.swift, its
// one bridge to Foundation, as tools/check-no-foundation.sh compiles them: the module then links no Foundation,
// which the Wasm SDK would otherwise bring in whole (the plan's first lever, the owner's choice of 2026-11-09).
let package = Package(
    name: "GPKitPlayground",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "GPKit",
            path: "Sources/GPKitCore",
            exclude: ["Date.swift", "GPKit.docc"],
            swiftSettings: [.unsafeFlags(["-Osize"])]
        ),
        .target(
            name: "PlaygroundAnswers",
            dependencies: ["GPKit"],
            swiftSettings: [.unsafeFlags(["-Osize"])]
        ),
        // the module the page loads: build it alone, --product GPKitPlayground, for WebAssembly
        .executableTarget(
            name: "GPKitPlayground",
            dependencies: ["PlaygroundAnswers"],
            swiftSettings: [.unsafeFlags(["-Osize"])],
            linkerSettings: [.unsafeFlags(["-Xclang-linker", "-mexec-model=reactor", "-Xlinker", "--strip-all"], .when(platforms: [.wasi]))]
        ),
        // the same answers worked out natively, for CI to hold the module's equal to: --product playground-reference
        .executableTarget(
            name: "playground-reference",
            dependencies: ["PlaygroundAnswers"]
        ),
    ]
)
