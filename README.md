# TagLibSwift

TagLibSwift is a Swift Package that wraps the [TagLib](https://github.com/taglib/taglib) C++ library as an XCFramework for iOS and macOS. It provides a convenient way to read and edit audio metadata in various formats.

## Building TagLib

### Prerequisites

- Xcode 12.0 or later
- CMake 3.15 or later
- iOS SDK 13.0 or later
- macOS SDK 10.15 or later

### Build Process

1. Clone the repository with submodules:

```bash
git clone --recursive https://github.com/jeonghi/TagLibSwift.git
cd TagLibSwift
```

2. Run the build script:

```bash
./build.sh
```

The build script performs the following steps:

- Builds TagLib for iOS (device + simulator) using ios-cmake
- Builds TagLib for macOS
- Creates a universal binary for iOS
- Generates TagLib.xcframework

### Build Output

The build process creates:

- `build-ios/`: iOS build artifacts
- `build-macos/`: macOS build artifacts
- `install/`: Installed headers and libraries
- `TagLib.xcframework/`: Final XCFramework for Swift Package Manager

### CMake Configuration

The project uses [ios-cmake](https://github.com/leetal/ios-cmake) for iOS builds with the following settings:

- Platform: OS64COMBINED (Universal binary for iOS)
- Build type: Release
- Installation directory: `install/ios` and `install/macos`

## Running Tests

Before running tests, you need to generate test audio files:

```bash
cd Tests/TagLibSwiftTests/Resources
./create_test_mp3.sh
```

This will create the necessary test MP3 files for running the test suite.

## License

TagLibSwift is released under the [MIT License](LICENSE). TagLib is licensed under [LGPL v2.1](https://github.com/taglib/taglib/blob/master/COPYING.LGPL).
