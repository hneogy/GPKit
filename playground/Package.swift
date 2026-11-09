// swift-tools-version: 6.0

import PackageDescription

// The playground of gpkit.gppasses.com (GPKit 2.0-b): GPKit compiled to WebAssembly as a WASI reactor, called by the
// page's script through a few exported functions, with no request of its own and no clock: the page passes the time
// in. A package of its own beside GPKit's, as pygpkit's is, so that its WebAssembly linker flags are never GPKit's.
let package = Package(
    name: "GPKitPlayground",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "GPKit", path: "..")],
    targets: [
        .executableTarget(
            name: "GPKitPlayground",
            dependencies: [.product(name: "GPKit", package: "GPKit")],
            swiftSettings: [.unsafeFlags(["-Osize"])],
            linkerSettings: [.unsafeFlags(["-Xclang-linker", "-mexec-model=reactor", "-Xlinker", "--gc-sections", "-Xlinker", "--strip-all"], .when(platforms: [.wasi]))]
        ),
    ]
)
