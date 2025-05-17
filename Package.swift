// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "TagLibSwift",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "TagLibSwift",
            targets: ["TagLibSwift"]
        ),
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "TagLib",
            path: "TagLib.xcframework"
        ),
        .target(
            name: "TagLibCBridge",
            dependencies: ["TagLib"],
            path: "Sources/TagLibCBridge",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("../TagLib.xcframework/Headers"),
                .unsafeFlags(["-std=c++17"])
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "TagLibSwift",
            dependencies: ["TagLibCBridge", "TagLib"],
            path: "Sources/TagLibSwift",
            swiftSettings: [
                .unsafeFlags(["-import-objc-header", "Sources/TagLibSwift/TagLib-Bridging-Header.h"])
            ]
        ),
        .testTarget(
            name: "TagLibSwiftTests",
            dependencies: ["TagLibSwift"],
            path: "Tests/TagLibSwiftTests",
            resources: [
                .process("Resources")
            ]
        )
    ]
) 