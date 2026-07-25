# TagLibSwift

Read and write audio metadata in Swift, powered by [TagLib](https://github.com/taglib/taglib) 2.3.1.

[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013%20%7C%20macOS%2010.15-blue.svg)](#requirements)
[![SPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](#installation)
[![TagLib](https://img.shields.io/badge/TagLib-2.3.1-informational.svg)](https://taglib.org)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

TagLibSwift wraps the TagLib C++ library as a Swift package for iOS and macOS. TagLib's source is **compiled from vendored source by SwiftPM** — no prebuilt binary, no CMake step, and full iOS device **and simulator** support out of the box.

---

## Features

- 📖 **Read & write** tags for MP3/ID3v2, FLAC, MP4/M4A, Ogg Vorbis, WAV/AIFF, APE, WavPack, and more.
- 🎛️ **Two products** — a minimal pure-Swift API, and a full-power API over TagLib's complete C++ surface via opt-in Swift/C++ interop.
- 🗂️ **Universal metadata** — the format-independent PropertyMap exposes every text tag (`ALBUMARTIST`, `COMPOSER`, `DISCNUMBER`, `BPM`, …) as a plain `[String: [String]]`.
- 🖼️ **Cover art** — read and write embedded pictures as `Data`.
- 🎚️ **Audio properties** — bitrate, length, sample rate, channels.
- 🧩 **Escape hatch** — drop down to raw TagLib C++ for format-specific work when you need it.
- ✅ **Tested** — 37 tests across MP3/FLAC/M4A/Ogg with 100% line coverage of the Swift API.

## Requirements

| | Minimum |
|---|---|
| Swift | 5.9 |
| Xcode | 15 |
| iOS | 13.0 |
| macOS | 10.15 |

> `TagLibSwiftCxx` (the interop product) may raise its own floor if you opt into reference-type imports; the default value-type API keeps the iOS 13 / macOS 10.15 floor.

## Installation

### Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/jeonghi/TagLibSwift.git", from: "0.1.0")
]
```

Then add the product you need to your target:

```swift
// Minimal, pure-Swift — no extra build settings.
.target(name: "MyApp", dependencies: [
    .product(name: "TagLibSwift", package: "TagLibSwift")
])

// Full API via C++ interop — the consuming target must enable interop (see below).
.target(
    name: "MyApp",
    dependencies: [.product(name: "TagLibSwiftCxx", package: "TagLibSwift")],
    swiftSettings: [.interoperabilityMode(.Cxx)]
)
```

In **Xcode**, add the package via *File ▸ Add Package Dependencies…*. For `TagLibSwiftCxx`, set **Build Settings ▸ C++ and Objective-C Interoperability** to **C++/Objective-C++** on the consuming target.

## Products

Pick the library that matches how much of TagLib you need:

| Product | API | Swift/C++ interop | Use it when |
|---|---|---|---|
| **`TagLibSwift`** | Pure-Swift `TagFile` over a C ABI bridge. Common tags + save. | No | You want the smallest, most portable footprint and only need common tags. |
| **`TagLibSwiftCxx`** | Ergonomic `AudioFile` over TagLib's C++ types. Adds PropertyMap, cover art, audio properties, and a raw escape hatch. | **Yes (opt-in)** | You need the full metadata model or format-specific access. |

### The interop opt-in

`TagLibSwiftCxx` uses Swift/C++ interoperability, so any target depending on it **must enable C++ interop** (`.interoperabilityMode(.Cxx)` in SwiftPM, or *C++/Objective-C++* in Xcode). Because C++ interop is not yet ABI-stable, treat adopting `TagLibSwiftCxx` as a deliberate, toolchain-pinned choice. Need only common tags? Stay on `TagLibSwift`.

## Quick Start

### `TagLibSwiftCxx` — the `AudioFile` API

```swift
import TagLibSwiftCxx
import Foundation

guard let file = AudioFile(path: "/path/to/song.flac") else { return }

// Read
print(file.title, "—", file.artist)
print(file.bitrate ?? 0, "kbps,", file.lengthInSeconds ?? 0, "s")

// Write common tags
file.title = "New Title"
file.year = 2026

// Universal, format-independent text tags
var props = file.properties
props["COMPOSER"] = ["Jane Doe"]
let unsupported = file.setProperties(props)   // returns any keys this format rejected

// Cover art
file.setPictures([
    Picture(data: try Data(contentsOf: coverURL),
            mimeType: "image/png",
            description: "cover",
            pictureType: .frontCover)
])

try file.save()
```

`setProperties(_:)` returns the keys the format could not store (empty means everything was written) — so partial writes are never silent.

### `TagLibSwift` — the pure-Swift API

```swift
import TagLibSwift

let file = try TagFile(path: "/path/to/song.mp3")
file.artist = "New Artist"
file.year = 2026
try file.save()
```

### Escape hatch

When the typed API doesn't cover a format-specific need (e.g. individual ID3v2 frames), reach the underlying TagLib type:

```swift
let ref = file.fileRef   // TagLib.FileRef — use TagLib's C++ API directly
```

## Supported formats

MP3 (ID3v1/ID3v2), FLAC, Ogg (Vorbis/Opus/Speex/FLAC), MP4/M4A, WAV, AIFF, APE, WavPack, Musepack, TrueAudio, ASF/WMA, Matroska, DSF/DSDIFF, and tracker formats (MOD/IT/S3M/XM) — everything TagLib 2.3.1 supports.

## Versioning

TagLibSwift vendors **TagLib 2.3.1**. The upstream source lives in-repo, so consumers need no submodules to build. Maintainers bumping the vendored TagLib version should follow [UPDATING.md](UPDATING.md).

## Testing

```bash
swift test
```

The pure-Swift tests use a fixture generated by `Tests/TagLibSwiftTests/Resources/create_test_mp3.sh` (requires `ffmpeg`). The `TagLibSwiftCxx` multi-format tests generate their FLAC/M4A/Ogg fixtures automatically at runtime, skipping cleanly if `ffmpeg` or a required encoder is unavailable.

## License

TagLibSwift is released under the [MIT License](LICENSE). TagLib is licensed under [LGPL v2.1](https://github.com/taglib/taglib/blob/master/COPYING.LGPL).
