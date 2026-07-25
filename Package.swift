// swift-tools-version:5.9
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
            name: "CTagLib",
            path: "Sources/CTagLib",
            exclude: ["README.md"],
            publicHeadersPath: ".",
            cSettings: [],
            cxxSettings: [
                .headerSearchPath("config"),
                .headerSearchPath("."),
                .headerSearchPath("taglib"),
                .headerSearchPath("taglib/toolkit"),
                .headerSearchPath("taglib/mpeg"),
                .headerSearchPath("taglib/mpeg/id3v1"),
                .headerSearchPath("taglib/mpeg/id3v2"),
                .headerSearchPath("taglib/mpeg/id3v2/frames"),
                .headerSearchPath("taglib/ogg"),
                .headerSearchPath("taglib/ogg/flac"),
                .headerSearchPath("taglib/ogg/vorbis"),
                .headerSearchPath("taglib/ogg/speex"),
                .headerSearchPath("taglib/ogg/opus"),
                .headerSearchPath("taglib/flac"),
                .headerSearchPath("taglib/mp4"),
                .headerSearchPath("taglib/mpc"),
                .headerSearchPath("taglib/riff"),
                .headerSearchPath("taglib/riff/aiff"),
                .headerSearchPath("taglib/riff/wav"),
                .headerSearchPath("taglib/ape"),
                .headerSearchPath("taglib/wavpack"),
                .headerSearchPath("taglib/trueaudio"),
                .headerSearchPath("taglib/asf"),
                .headerSearchPath("taglib/mod"),
                .headerSearchPath("taglib/it"),
                .headerSearchPath("taglib/s3m"),
                .headerSearchPath("taglib/xm"),
                .headerSearchPath("taglib/dsf"),
                .headerSearchPath("taglib/dsdiff"),
                .headerSearchPath("taglib/matroska"),
                .headerSearchPath("taglib/matroska/ebml"),
                .headerSearchPath("taglib/shorten"),
                .headerSearchPath("utfcpp"),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("c++"),
            ]
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
                .linkedLibrary("c++"),
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "TagLibSwift",
            dependencies: ["TagLibCBridge", "TagLib"],
            path: "Sources/TagLibSwift"
        ),
        .testTarget(
            name: "TagLibSwiftTests",
            dependencies: ["TagLibSwift"],
            path: "Tests/TagLibSwiftTests",
            resources: [
                .process("Resources")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)