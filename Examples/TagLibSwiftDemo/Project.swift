import ProjectDescription

// TagLibSwiftDemo — a multiplatform (iOS + macOS) SwiftUI example app that
// exercises every feature of the TagLibSwift SDK.
//
// The app depends on the TagLibSwift package by relative path (../..) and MUST
// enable C++ interop (SWIFT_OBJC_INTEROP_MODE = objcxx), otherwise
// `import TagLibSwift` will not compile.
//
// Generate the standalone .xcodeproj with:  tuist generate --no-open
let project = Project(
    name: "TagLibSwiftDemo",
    packages: [
        .package(path: "../..")
    ],
    settings: .settings(
        base: [
            "SWIFT_OBJC_INTEROP_MODE": "objcxx",
            "SWIFT_VERSION": "5.9",
            "CLANG_CXX_LANGUAGE_STANDARD": "gnu++17"
        ]
    ),
    targets: [
        .target(
            name: "TagLibSwiftDemo",
            destinations: [.iPhone, .iPad, .mac],
            product: .app,
            bundleId: "com.taglibswift.demo",
            deploymentTargets: .multiplatform(iOS: "16.0", macOS: "13.0"),
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [:],
                    "CFBundleDisplayName": "TagLibSwiftDemo",
                    "NSPhotoLibraryUsageDescription":
                        "Pick an image to embed as cover art in the audio file."
                ]
            ),
            sources: ["TagLibSwiftDemo/Sources/**"],
            resources: ["TagLibSwiftDemo/Resources/**"],
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": true,
                "com.apple.security.files.user-selected.read-write": true,
                "com.apple.security.files.user-selected.read-only": true
            ]),
            dependencies: [
                .package(product: "TagLibSwift")
            ],
            settings: .settings(
                base: [
                    "SWIFT_OBJC_INTEROP_MODE": "objcxx"
                ]
            )
        )
    ]
)
