// swift-tools-version: 6.0

import PackageDescription

// The playground of gpkit.gppasses.com (GPKit 2.0-b): GPKit compiled to WebAssembly as a WASI reactor, called by the
// page's script through a few exported functions, with no request of its own and no clock: the page passes the time
// in. A package of its own beside GPKit's, as pygpkit's is, so that its WebAssembly linker flags are never GPKit's.
//
// GPKit is built here from its own sources (Sources/GPKitCore is a link to ../Sources/GPKit) without Date.swift, its
// one bridge to Foundation, as tools/check-no-foundation.sh compiles them: the module then links no Foundation,
// which the Wasm SDK would otherwise bring in whole (the plan's first lever, the owner's choice of 2026-11-09).
//
// For measuring in CI alone (playground/measure.sh), three switches; with none set, the build is the one the page gets:
//   GPKIT_PLAYGROUND_OPT=O         -O in place of -Osize
//   GPKIT_PLAYGROUND_GC=0          no --gc-sections
//   GPKIT_PLAYGROUND_STRIP=0       no --strip-all, so the module keeps its function names for a profiler
let environment = Context.environment
let optimise = environment["GPKIT_PLAYGROUND_OPT"] == "O" ? "-O" : "-Osize"
var linking = ["-Xclang-linker", "-mexec-model=reactor"]
if environment["GPKIT_PLAYGROUND_GC"] != "0" { linking += ["-Xlinker", "--gc-sections"] }
if environment["GPKIT_PLAYGROUND_STRIP"] != "0" { linking += ["-Xlinker", "--strip-all"] }

let package = Package(
    name: "GPKitPlayground",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "GPKit",
            path: "Sources/GPKitCore",
            exclude: ["Date.swift", "GPKit.docc"],
            swiftSettings: [.unsafeFlags([optimise])]
        ),
        .executableTarget(
            name: "GPKitPlayground",
            dependencies: ["GPKit"],
            swiftSettings: [.unsafeFlags([optimise])],
            linkerSettings: [.unsafeFlags(linking, .when(platforms: [.wasi]))]
        ),
    ]
)
