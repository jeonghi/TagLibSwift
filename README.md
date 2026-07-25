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
- 🧬 **Generic complex properties** — read/write any complex-property key (`PICTURE`, `GENERALOBJECT`, …) as typed `ComplexValue` maps.
- 🎚️ **Audio properties** — bitrate, length, sample rate, channels, plus `bitsPerSample` and MPEG version/layer where the format provides them.
- 💾 **In-memory I/O** — open from and serialize back to `Data`, no file path required.
- 🧩 **Escape hatch** — drop down to the raw `TagLib.FileRef` for format-specific work when you need it.
- ✅ **Tested** — 34 tests across MP3/FLAC/M4A/Ogg (path and in-memory) with 100% line coverage of the Swift API.

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

### In-memory files

Open audio straight from bytes (e.g. a download) and serialize the edited bytes back out — no temp file needed:

```swift
guard let file = AudioFile(data: mp3Data, fileExtension: "mp3") else { return }
file.tag.title = "New Title"
try file.save()                 // writes back into the in-memory stream
let updated: Data = try file.serialized()   // reopen with AudioFile(data:fileExtension:)
```

`serialized()` throws `AudioFileError.notMemoryBacked` on a path-backed file.

### Generic complex properties

Beyond cover art, any complex-property key is reachable as typed `ComplexValue` maps:

```swift
for key in file.complexPropertyKeys {            // e.g. "PICTURE", "GENERALOBJECT"
    let maps = file.complexProperties(key)       // [[String: ComplexValue]]
    // ComplexValue: .string / .int / .bool / .data / .stringList / .unsupported
}
file.setComplexProperties("PICTURE", newMaps)    // then save()
```

`pictures` / `setPictures(_:)` are a thin, typed layer over the `PICTURE` key.

### API at a glance

| Member | TagLib equivalent | Notes |
|---|---|---|
| `AudioFile(path:)` | `FileRef(path)` | Returns `nil` if the file could not be parsed. |
| `AudioFile(data:fileExtension:)` | `FileRef(IOStream*)` | Opens from an in-memory `Data` buffer via a `ByteVectorStream`. |
| `try file.serialized()` | `ByteVectorStream::data()` | In-memory bytes after `save()`; throws for path-backed files. |
| `file.isValid` / `file.isNull` | `FileRef::isNull` | Validity of the parsed file. |
| `file.tag` | `FileRef::tag()` | Live view: `title`, `artist`, `album`, `comment`, `genre`, `year`, `track`, `isEmpty`. Setters persist on `save()`. |
| `file.audioProperties` | `FileRef::audioProperties()` | Optional; `lengthInSeconds`, `lengthInMilliseconds`, `bitrate`, `sampleRate`, `channels`, `bitsPerSample?`, `mpegVersion?`, `mpegLayer?`. |
| `file.properties` / `setProperties(_:)` | `FileRef::properties()` / `setProperties()` | `PropertyMap` = `[String: [String]]`. `setProperties` returns rejected keys. |
| `file.complexPropertyKeys` / `complexProperties(_:)` / `setComplexProperties(_:_:)` | `FileRef::complexProperty*` | Any complex-property key as `[[String: ComplexValue]]`. |
| `file.pictures` / `setPictures(_:)` | complex property `"PICTURE"` | Cover art as `Picture` values (typed layer over the `PICTURE` key). |
| `try file.save()` | `FileRef::save()` | Throws `AudioFileError.saveFailed`. |

### Escape hatch

When the typed API doesn't cover a format-specific need (e.g. individual ID3v2 frames), reach the underlying TagLib type:

```swift
let ref = file.fileRef   // TagLib.FileRef — use TagLib's C++ API directly
```

## Feature coverage

How far the Swift surface covers TagLib. Because the whole library is compiled in
and reachable through `file.fileRef`, **everything TagLib can do is accessible** —
the checklist distinguishes what's wrapped in an idiomatic Swift API from what you
reach through the raw escape hatch.

**Legend:** ✅ high-level Swift API · 🔶 reachable via raw `file.fileRef` (C++ interop), not pre-wrapped · ❌ not available

| TagLib capability | Status | Swift API |
|---|:--:|---|
| **Basic tags** — title, artist, album, comment, genre, year, track | ✅ | `file.tag` |
| **Universal text tags** — PropertyMap (`ALBUMARTIST`, `COMPOSER`, `DISCNUMBER`, `BPM`, `LYRICS`, …, any key) | ✅ | `file.properties` / `setProperties(_:)` |
| **Rejected-key reporting** on write | ✅ | `setProperties(_:)` return value |
| **Cover art / pictures** — complex `PICTURE` property | ✅ | `file.pictures` / `setPictures(_:)` |
| **Generic complex properties** — any key as typed `ComplexValue` maps | ✅ | `file.complexPropertyKeys` / `complexProperties(_:)` / `setComplexProperties(_:_:)` |
| **Audio properties** — length, bitrate, sample rate, channels | ✅ | `file.audioProperties` |
| **Extended audio props** — `bitsPerSample` (FLAC/WAV/AIFF/MP4/APE/WavPack/TrueAudio/DSF/DSDIFF), MPEG version/layer | ✅ | `file.audioProperties.bitsPerSample` / `.mpegVersion` / `.mpegLayer` |
| **In-memory / IOStream / ByteVector I/O** (no file path) | ✅ | `AudioFile(data:fileExtension:)` / `try file.serialized()` |
| **Save to disk** | ✅ | `try file.save()` |
| **File validity** — isNull / isValid | ✅ | `file.isValid` / `file.isNull` |
| **All TagLib file formats** (auto-detected) — the API above works on every [supported format](#supported-formats) | ✅ | `AudioFile(path:)` |
| **Format-specific tag content** — ID3v2 / MP4 / Xiph / APE / ASF metadata | ✅ | `file.properties` (text) · `complexProperties(_:)` (binary/structured) |
| **Format-specific tag _classes_** — raw ID3v2 frames (chapters, USLT lyrics, POPM rating, TXXX…), MP4 atoms, Xiph/APE/ASF objects | 🔶 | `file.fileRef` |
| **Per-version tag strip/remove** (ID3v1 vs ID3v2, etc.) | 🔶 | `file.fileRef` |

The high-level API now covers TagLib's **portable metadata model** end to end —
base tags, the universal PropertyMap (every text tag), generic complex properties
(cover art and any other key), extended audio properties, and in-memory I/O —
across all formats. The remaining 🔶 rows are, by design, thin: the _content_ of
format-specific tags is already reachable through `properties` (text) and
`complexProperties` (binary/structured), so wrapping each raw frame/atom _class_
(hundreds of format-specific APIs) and per-version tag stripping stay reachable
through the raw `file.fileRef` escape hatch rather than being pre-wrapped.

## Example app

A multiplatform (iOS + macOS) SwiftUI demo lives in [`Examples/TagLibSwiftDemo/`](Examples/TagLibSwiftDemo/). Open `Examples/TagLibSwiftDemo/TagLibSwiftDemo.xcodeproj` in Xcode and run — it exercises the full API: opening an `AudioFile`, editing `tag.*`, reading `audioProperties`, editing the `PropertyMap` (showing rejected keys on save), viewing/setting cover art (`pictures` / `setPictures`), and `save()`. It ships a tiny tagged sample MP3 that it copies to a writable temp location before opening (the bundle is read-only), plus a `.fileImporter` to open other files.

The demo target enables C++ interop via the build setting **`SWIFT_OBJC_INTEROP_MODE = objcxx`** — required for `import TagLibSwift` to compile. The project is generated from `Project.swift` with [tuist](https://tuist.dev) (`tuist generate`), but the committed `.xcodeproj` is standalone and opens/builds without tuist.

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
