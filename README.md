# TagLibSwift

TagLibSwift is a Swift Package that wraps the [TagLib](https://github.com/taglib/taglib) C++ library for iOS and macOS. It provides a convenient way to read and edit audio metadata in various formats.

## Two products

The package ships **two libraries**. Pick the one that matches how much of TagLib you need:

| Product | What it is | C++ interop | Deployment floor |
|---|---|---|---|
| `TagLibSwift` | Pure-Swift API over a C ABI bridge. Simple read/write of common tags. No Swift/C++ interop — links as an ordinary Swift/C module. | No | iOS 13 / macOS 10.15 |
| `TagLibSwiftCxx` | Ergonomic, higher-level API (`AudioFile`) layered directly on TagLib's C++ types via **Swift/C++ interop**. Adds the universal PropertyMap, cover art, and a raw escape hatch to format-specific classes. | **Yes (opt-in)** | iOS 13 / macOS 10.15 |

### Choosing `TagLibSwiftCxx` — the interop opt-in

`TagLibSwiftCxx` uses Swift/C++ interoperability. Any target that depends on it (or transitively imports it) **must enable C++ interop** in its own build settings:

- **SwiftPM:** add `swiftSettings: [.interoperabilityMode(.Cxx)]` to the consuming target.
- **Xcode:** set **C++ and Objective-C Interoperability** to **C++/Objective-C++** (`SWIFT_OBJC_INTEROP_MODE = objcxx`) on the consuming target.

Because C++ interop is not yet ABI-stable, enabling it is a **build-setting / semver consideration** for your app: treat a move to `TagLibSwiftCxx` as an opt-in that pins your toolchain expectations. If you only need common tags and want the smallest, most portable footprint, stay on `TagLibSwift`.

## Usage

### `TagLibSwiftCxx` — the `AudioFile` API

```swift
import TagLibSwiftCxx
import Foundation

// Open a file (nil if TagLib can't parse it).
guard let file = AudioFile(path: "/path/to/song.flac") else { return }

// Read base tags and audio properties.
print(file.title, file.artist, file.album)
print(file.bitrate ?? 0, "kbps,", file.lengthInSeconds ?? 0, "s")

// Write base tags.
file.title = "New Title"
file.year = 2026

// The universal, format-independent text-tag map (ALBUMARTIST, COMPOSER, BPM, ...).
var props = file.properties
props["COMPOSER"] = ["Jane Doe"]
file.properties = props

// Cover art (complex "PICTURE" property).
let art = Picture(
    data: try Data(contentsOf: coverURL),
    mimeType: "image/png",
    description: "cover",
    pictureType: .frontCover
)
file.setPictures([art])
for picture in file.pictures {
    print(picture.mimeType, picture.data.count, "bytes")
}

// Persist all pending changes.
try file.save()
```

#### Raw escape hatch

`AudioFile.fileRef` exposes the underlying `TagLib::FileRef` for format-specific
work the high-level API doesn't cover (e.g. reaching individual ID3v2 frames).
It's the deliberate escape hatch: everything the typed accessors cover should go
through them, but the raw ref is there when you need TagLib directly.

```swift
let ref = file.fileRef // TagLib.FileRef — use TagLib's C++ API directly
```

### `TagLibSwift` — the pure-Swift API

See the tests in `Tests/TagLibSwiftTests` for the pure-Swift surface. It requires
no interop build setting and reads/writes the common tag fields.

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

The `TagLibSwiftCxx` multi-format smoke tests (FLAC, MP4/M4A, Ogg Vorbis)
generate their fixtures automatically at runtime with `ffmpeg` into a temp
directory — no manual step is needed, and each format is skipped with a clear
message if `ffmpeg` or the required encoder is missing. To produce the same
fixtures by hand (e.g. for inspection), run
`Tests/TagLibSwiftCxxTests/Resources/create_test_fixtures.sh`.

## License

TagLibSwift is released under the [MIT License](LICENSE). TagLib is licensed under [LGPL v2.1](https://github.com/taglib/taglib/blob/master/COPYING.LGPL).
