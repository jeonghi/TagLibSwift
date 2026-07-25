# TagLibSwift

TagLibSwift is a Swift Package that wraps the [TagLib](https://github.com/taglib/taglib) C++ library for iOS and macOS. It provides a convenient way to read and edit audio metadata in various formats.

## Building

This package compiles TagLib 2.3.1 from vendored source via SwiftPM; no separate build step is required. Clone the repository with submodules and build normally:

```bash
git clone --recursive https://github.com/jeonghi/TagLibSwift.git
cd TagLibSwift
swift build
```

## Running Tests

Before running tests, you need to generate test audio files:

```bash
cd Tests/TagLibSwiftTests/Resources
./create_test_mp3.sh
```

This will create the necessary test MP3 files for running the test suite.

## License

TagLibSwift is released under the [MIT License](LICENSE). TagLib is licensed under [LGPL v2.1](https://github.com/taglib/taglib/blob/master/COPYING.LGPL).
