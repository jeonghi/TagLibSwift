# TagLibSwift

TagLibSwift is a Swift Package that wraps the [TagLib](https://github.com/taglib/taglib) C++ library for iOS and macOS. It provides a convenient way to read and edit audio metadata in various formats.

## Building

This package compiles TagLib 2.3.1 from vendored source via SwiftPM; no separate build step is required. The TagLib source is vendored directly into this repository, so a plain clone (or adding TagLibSwift as a SwiftPM dependency) is all that's needed — no git submodules to initialize:

```bash
git clone https://github.com/jeonghi/TagLibSwift.git
cd TagLibSwift
swift build
```

> **Maintainers:** this repo also keeps a `taglib` git submodule as the source-of-truth checkout used to produce the vendored copy. It's only relevant when bumping TagLib to a new version — see [UPDATING.md](UPDATING.md).

## Running Tests

Before running tests, you need to generate test audio files:

```bash
cd Tests/TagLibSwiftTests/Resources
./create_test_mp3.sh
```

This will create the necessary test MP3 files for running the test suite.

## License

TagLibSwift is released under the [MIT License](LICENSE). TagLib is licensed under [LGPL v2.1](https://github.com/taglib/taglib/blob/master/COPYING.LGPL).
