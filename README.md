# TagLibSwift

Read and write audio metadata in Swift, powered by [TagLib](https://github.com/taglib/taglib) 2.3.1.

[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013%20%7C%20macOS%2010.15-blue.svg)](#requirements)
[![SPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](#installation)
[![TagLib](https://img.shields.io/badge/TagLib-2.3.1-informational.svg)](https://taglib.org)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

TagLibSwift wraps the TagLib C++ library as a Swift package for iOS and macOS. TagLib's source is **compiled from vendored source by SwiftPM** — no prebuilt binary, no CMake step, and full iOS device **and simulator** support out of the box.

The public API mirrors TagLib's own model — open a file, then reach its `tag`, `audioProperties`, `properties`, and `pictures`, and `save()` — layered over TagLib's C++ types via Swift/C++ interop.

---

## Features

- 📖 **Read & write** tags for MP3/ID3v2, FLAC, MP4/M4A, Ogg Vorbis, WAV/AIFF, APE, WavPack, and more.
- 🧱 **TagLib-faithful API** — a single `AudioFile` handle exposing `tag`, `audioProperties`, `properties`, `pictures`, and `save()`, mirroring `TagLib::FileRef`.
- 🗂️ **Universal metadata** — the format-independent `PropertyMap` exposes every text tag (`ALBUMARTIST`, `COMPOSER`, `DISCNUMBER`, `BPM`, …) as a plain `[String: [String]]`.
- 🖼️ **Cover art** — read and write embedded pictures as `Data`.
- 🎚️ **Audio properties** — bitrate, length, sample rate, channels.
- 🧩 **Escape hatch** — drop down to the raw `TagLib.FileRef` for format-specific work when you need it.
- ✅ **Tested** — 22 tests across MP3/FLAC/M4A/Ogg with 100% line coverage of the Swift API.

## Requirements

| | Minimum |
|---|---|
| Swift | 5.9 |
| Xcode | 15 |
| iOS | 13.0 |
| macOS | 10.15 |

## Installation

### Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/jeonghi/TagLibSwift.git", from: "0.1.0")
]
```

Then add the product to your target. **TagLibSwift uses Swift/C++ interoperability, so any target that depends on it must enable C++ interop:**

```swift
.target(
    name: "MyApp",
    dependencies: [.product(name: "TagLibSwift", package: "TagLibSwift")],
    swiftSettings: [.interoperabilityMode(.Cxx)]
)
```

In **Xcode**, add the package via *File ▸ Add Package Dependencies…*, then set **Build Settings ▸ C++ and Objective-C Interoperability** to **C++/Objective-C++** on the consuming target.

> Because Swift/C++ interop is not yet ABI-stable, treat adopting TagLibSwift as a deliberate, toolchain-pinned choice. The API rides the value-type interop path (no imported reference types), which preserves the iOS 13 / macOS 10.15 floor.

## Quick Start

```swift
import TagLibSwift
import Foundation

guard let file = AudioFile(path: "/path/to/song.flac") else { return }

// Read common tags
print(file.tag.title, "—", file.tag.artist)

// Read audio properties
if let audio = file.audioProperties {
    print(audio.bitrate, "kbps,", audio.lengthInSeconds, "s")
}

// Write common tags
file.tag.title = "New Title"
file.tag.year = 2026

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

### API at a glance

| Member | TagLib equivalent | Notes |
|---|---|---|
| `AudioFile(path:)` | `FileRef(path)` | Returns `nil` if the file could not be parsed. |
| `file.isValid` / `file.isNull` | `FileRef::isNull` | Validity of the parsed file. |
| `file.tag` | `FileRef::tag()` | Live view: `title`, `artist`, `album`, `comment`, `genre`, `year`, `track`, `isEmpty`. Setters persist on `save()`. |
| `file.audioProperties` | `FileRef::audioProperties()` | Optional; `lengthInSeconds`, `lengthInMilliseconds`, `bitrate`, `sampleRate`, `channels`. |
| `file.properties` / `setProperties(_:)` | `FileRef::properties()` / `setProperties()` | `PropertyMap` = `[String: [String]]`. `setProperties` returns rejected keys. |
| `file.pictures` / `setPictures(_:)` | complex property `"PICTURE"` | Cover art as `Picture` values. |
| `try file.save()` | `FileRef::save()` | Throws `AudioFileError.saveFailed`. |

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

The base tests use a committed MP3 fixture (regenerate with `Tests/TagLibSwiftTests/Resources/create_test_mp3.sh`, requires `ffmpeg`). The multi-format tests generate their FLAC/M4A/Ogg fixtures automatically at runtime, skipping cleanly if `ffmpeg` or a required encoder is unavailable.

## License

TagLibSwift is released under the [MIT License](LICENSE). TagLib is licensed under [LGPL v2.1](https://github.com/taglib/taglib/blob/master/COPYING.LGPL).
