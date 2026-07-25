import CTagLibCore
import CxxStdlib
import Foundation

/// A format-independent map of text tags, mirroring `TagLib::PropertyMap`:
/// each key (`TITLE`, `ARTIST`, `ALBUMARTIST`, `COMPOSER`, `DISCNUMBER`, `BPM`,
/// …) maps to an ordered list of string values.
public typealias PropertyMap = [String: [String]]

/// Errors thrown by ``AudioFile``.
public enum AudioFileError: Error, Equatable {
    /// Persisting tag changes to disk failed.
    case saveFailed
    /// ``AudioFile/serialized()`` was called on a path-backed file, which has no
    /// in-memory byte buffer to return. Open with ``AudioFile/init(data:fileExtension:)``.
    case notMemoryBacked
}

/// A handle to an audio file's metadata, layered over TagLib's C++ API via
/// Swift/C++ interop. Mirrors the shape of `TagLib::FileRef`: open a path, then
/// reach ``tag``, ``audioProperties``, ``properties``, and ``pictures``, and
/// persist edits with ``save()``.
///
/// `AudioFile` wraps a `TagLib::FileRef`. `FileRef` is copyable and shares the
/// underlying parsed file through a `shared_ptr`, so mutating a tag and then
/// calling ``save()`` operates on the same in-memory file. Because a file handle
/// is naturally reference-like (identity + mutable shared state), `AudioFile` is
/// a `final class` rather than a `struct`.
///
/// Everything here rides the value-type interop path (no imported reference
/// types), so the package's iOS 13 / macOS 10.15 deployment floor is preserved.
public final class AudioFile {

    /// The wrapped `TagLib::FileRef`. Exposed for the raw escape hatch: advanced
    /// callers can reach format-specific classes (ID3v2 frames, etc.) through it.
    /// Mutating it directly bypasses `AudioFile`'s conveniences; prefer the typed
    /// accessors below for anything they cover.
    public internal(set) var fileRef: TagLib.FileRef

    /// Opaque handle owning the `ByteVectorStream` + `FileRef` for a memory-backed
    /// file (see ``init(data:fileExtension:)``); `nil` for path-backed files.
    /// Freed in `deinit`.
    private let memoryHandle: UnsafeMutableRawPointer?

    /// Open the file at `path`. Returns `nil` if TagLib could not parse it.
    public init?(path: String) {
        let ref = path.withCString { TagLibInterop.openFile($0) }
        if ref.isNull() { return nil }
        self.fileRef = ref
        self.memoryHandle = nil
    }

    /// Open audio from an in-memory byte buffer instead of a file path.
    ///
    /// `fileExtension` (e.g. `"mp3"`, `"flac"`, without a leading dot) hints the
    /// format; TagLib falls back to sniffing the content if the extension does
    /// not resolve. Returns `nil` if the bytes could not be parsed.
    ///
    /// The instance owns a `ByteVectorStream` holding the bytes; edits go through
    /// ``save()`` (which writes back into that stream) and the updated bytes are
    /// read out with ``serialized()``.
    public init?(data: Data, fileExtension: String) {
        let handle: UnsafeMutableRawPointer? = data.withUnsafeBytes { raw in
            fileExtension.withCString { ext in
                TagLibInterop.openMemory(raw.baseAddress, raw.count, ext)
            }
        }
        guard let handle else { return nil }
        let ref = TagLibInterop.memoryFileRef(handle)
        // Extension-based detection yields a File object even for empty/garbage
        // bytes (unlike a bad path, which yields a null ref), so validate the
        // parse — not just null-ness — before accepting a memory-backed file.
        if !TagLibInterop.isValid(ref) {
            TagLibInterop.closeMemory(handle)
            return nil
        }
        self.fileRef = ref
        self.memoryHandle = handle
    }

    deinit {
        if let memoryHandle {
            TagLibInterop.closeMemory(memoryHandle)
        }
    }

    /// The current in-memory bytes of a memory-backed file (call after edits and
    /// ``save()``). Reopen the returned `Data` with ``init(data:fileExtension:)``.
    ///
    /// - Throws: ``AudioFileError/notMemoryBacked`` if this file was opened from a
    ///   path rather than from memory.
    public func serialized() throws -> Data {
        guard let memoryHandle else { throw AudioFileError.notMemoryBacked }
        let size = Int(TagLibInterop.memoryDataSize(memoryHandle))
        var data = Data(count: size)
        if size > 0 {
            data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                if let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) {
                    TagLibInterop.memoryCopyData(memoryHandle, base)
                }
            }
        }
        return data
    }

    /// Whether the underlying file was parsed successfully.
    public var isValid: Bool {
        TagLibInterop.isValid(fileRef)
    }

    /// Whether the wrapped `FileRef` is null (no file). Mirrors
    /// `TagLib::FileRef::isNull`. Always `false` for a live `AudioFile`, since
    /// ``init(path:)`` returns `nil` on a null ref.
    public var isNull: Bool {
        fileRef.isNull()
    }

    /// Persist pending tag changes to disk.
    /// - Throws: ``AudioFileError/saveFailed`` if TagLib reported a write failure.
    public func save() throws {
        if !TagLibInterop.save(&fileRef) {
            throw AudioFileError.saveFailed
        }
    }

    // MARK: - Base tag

    /// The common text/number fields (title, artist, album, comment, genre,
    /// year, track) as a live, settable view. Mirrors `FileRef::tag()`.
    public var tag: Tag {
        Tag(file: self)
    }

    // MARK: - Audio properties (read-only)

    /// Read-only audio characteristics, or `nil` if the file exposes none.
    /// Mirrors `FileRef::audioProperties()`.
    public var audioProperties: AudioProperties? {
        guard TagLibInterop.hasAudioProperties(fileRef) else { return nil }
        let bits = Int(TagLibInterop.bitsPerSample(fileRef))
        let mpegVer = Int(TagLibInterop.mpegVersion(fileRef))
        let mpegLay = Int(TagLibInterop.mpegLayer(fileRef))
        return AudioProperties(
            lengthInSeconds: Int(TagLibInterop.lengthInSeconds(fileRef)),
            lengthInMilliseconds: Int(TagLibInterop.lengthInMilliseconds(fileRef)),
            bitrate: Int(TagLibInterop.bitrate(fileRef)),
            sampleRate: Int(TagLibInterop.sampleRate(fileRef)),
            channels: Int(TagLibInterop.channels(fileRef)),
            bitsPerSample: bits >= 0 ? bits : nil,
            mpegVersion: mpegVer >= 0 ? AudioProperties.MPEGVersion(rawValue: mpegVer) : nil,
            mpegLayer: mpegLay >= 0 ? mpegLay : nil
        )
    }

    // MARK: - PropertyMap (the universal all-text-tags interface)

    /// All text tags as a format-independent map (`TagLib::PropertyMap`).
    ///
    /// Reading snapshots the file's current PropertyMap once on the C++ side and
    /// rebuilds it here via flat, index-addressed accessors. Writing replaces the
    /// tag's properties wholesale via `Tag::setProperties`; call ``save()`` to
    /// persist. Keys are format-independent (`ALBUMARTIST`, `COMPOSER`,
    /// `DISCNUMBER`, `BPM`, ...).
    public var properties: PropertyMap {
        get {
            let access = TagLibInterop.PropertyMapAccess(fileRef)
            var result: PropertyMap = [:]
            let keyCount = access.keyCount()
            var i: UInt32 = 0
            while i < keyCount {
                let key = String(access.key(i))
                let valueCount = access.valueCount(i)
                var values: [String] = []
                values.reserveCapacity(Int(valueCount))
                var j: UInt32 = 0
                while j < valueCount {
                    values.append(String(access.value(i, j)))
                    j += 1
                }
                result[key] = values
                i += 1
            }
            return result
        }
        set { setProperties(newValue) }
    }

    /// Replace all text tags with `props`. Call ``save()`` afterwards to persist.
    ///
    /// - Returns: The properties the format could **not** store (its rejected /
    ///   unsupported keys and their values). An empty map means every key was
    ///   accepted. TagLib's `setProperties` reports these so a partial write is
    ///   not silent data loss; inspect the result if you need to know.
    @discardableResult
    public func setProperties(_ props: PropertyMap) -> PropertyMap {
        var builder = TagLibInterop.PropertyMapBuilder()
        for (key, values) in props {
            if values.isEmpty {
                key.withCString { builder.ensureKey($0) }
                continue
            }
            for value in values {
                key.withCString { keyPtr in
                    value.withCString { valuePtr in
                        builder.append(keyPtr, valuePtr)
                    }
                }
            }
        }
        // Applied via a free function (not a builder method): passing an `inout`
        // FileRef to a member method of a Swift-held C++ value silently dropped
        // newly created frames. See applyProperties in taglib_interop.h.
        //
        // applyProperties returns the unsupported/rejected PropertyMap as a flat,
        // value-type snapshot (same crossing as reads); rebuild it here.
        let unsupported = TagLibInterop.applyProperties(&fileRef, builder)
        var result: PropertyMap = [:]
        let keyCount = unsupported.keyCount()
        var i: UInt32 = 0
        while i < keyCount {
            let key = String(unsupported.key(i))
            let valueCount = unsupported.valueCount(i)
            var values: [String] = []
            values.reserveCapacity(Int(valueCount))
            var j: UInt32 = 0
            while j < valueCount {
                values.append(String(unsupported.value(i, j)))
                j += 1
            }
            result[key] = values
            i += 1
        }
        return result
    }

    // MARK: - Generic complex properties

    /// The keys under which this file exposes complex properties (e.g.
    /// `"PICTURE"`, `"GENERALOBJECT"`). Mirrors `FileRef::complexPropertyKeys()`.
    public var complexPropertyKeys: [String] {
        let access = TagLibInterop.complexPropertyKeys(fileRef)
        var result: [String] = []
        let count = access.count()
        result.reserveCapacity(Int(count))
        var i: UInt32 = 0
        while i < count {
            result.append(String(access.at(i)))
            i += 1
        }
        return result
    }

    /// The complex property stored under `key` as a list of `VariantMap`s, each a
    /// `[String: ComplexValue]`. Mirrors `FileRef::complexProperties(key)`.
    public func complexProperties(_ key: String) -> [[String: ComplexValue]] {
        let access = key.withCString { TagLibInterop.ComplexPropertyAccess(fileRef, $0) }
        return AudioFile.decodeComplex(access)
    }

    /// Replace the complex property under `key`. Call ``save()`` to persist.
    /// Mirrors `FileRef::setComplexProperties(key, value)`.
    /// - Returns: `true` if the format accepted the write.
    @discardableResult
    public func setComplexProperties(_ key: String, _ value: [[String: ComplexValue]]) -> Bool {
        let builder = AudioFile.encodeComplex(value)
        // Free function, not a member method (see setProperties / applyProperties).
        return key.withCString { TagLibInterop.applyComplexProperties(&fileRef, $0, builder) }
    }

    /// Rebuild `[[String: ComplexValue]]` from a C++ snapshot. Factored out of
    /// ``complexProperties(_:)`` so every variant type (including int/bool/
    /// StringList, which no format persists) can be exercised via a direct crossing.
    private static func decodeComplex(
        _ access: TagLibInterop.ComplexPropertyAccess
    ) -> [[String: ComplexValue]] {
        var result: [[String: ComplexValue]] = []
        let mapCount = access.mapCount()
        result.reserveCapacity(Int(mapCount))
        var m: UInt32 = 0
        while m < mapCount {
            var map: [String: ComplexValue] = [:]
            let fieldCount = access.fieldCount(m)
            var f: UInt32 = 0
            while f < fieldCount {
                let key = String(access.fieldKey(m, f))
                switch access.fieldType(m, f) {
                case 0:
                    map[key] = .string(String(access.fieldString(m, f)))
                case 1:
                    map[key] = .int(Int(access.fieldInt(m, f)))
                case 2:
                    map[key] = .bool(access.fieldBool(m, f))
                case 3:
                    let size = Int(access.fieldDataSize(m, f))
                    var data = Data(count: size)
                    if size > 0 {
                        data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                            if let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) {
                                access.fieldCopyData(m, f, base)
                            }
                        }
                    }
                    map[key] = .data(data)
                case 4:
                    var values: [String] = []
                    let listCount = access.fieldListCount(m, f)
                    var i: UInt32 = 0
                    while i < listCount {
                        values.append(String(access.fieldListValue(m, f, i)))
                        i += 1
                    }
                    map[key] = .stringList(values)
                default:
                    map[key] = .unsupported
                }
                f += 1
            }
            result.append(map)
            m += 1
        }
        return result
    }

    /// Build a C++ `ComplexPropertyBuilder` from `[[String: ComplexValue]]`.
    /// `.unsupported` fields are skipped (nothing to serialize).
    private static func encodeComplex(
        _ maps: [[String: ComplexValue]]
    ) -> TagLibInterop.ComplexPropertyBuilder {
        var builder = TagLibInterop.ComplexPropertyBuilder()
        for map in maps {
            builder.startMap()
            for (key, value) in map {
                key.withCString { keyPtr in
                    switch value {
                    case let .string(string):
                        string.withCString { builder.setString(keyPtr, $0) }
                    case let .int(int):
                        builder.setInt(keyPtr, Int64(int))
                    case let .bool(bool):
                        builder.setBool(keyPtr, bool)
                    case let .data(data):
                        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                            let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self)
                            builder.setData(keyPtr, base, UInt32(data.count))
                        }
                    case let .stringList(values):
                        for value in values {
                            value.withCString { builder.addStringListItem(keyPtr, $0) }
                        }
                    case .unsupported:
                        break
                    }
                }
            }
        }
        builder.finish()
        return builder
    }

    // MARK: - Test seams for the value-type crossing

    // The complex-property C++ interop types (ComplexPropertyAccess / Builder) are
    // deliberately kept internal to this module — they don't cross the module
    // boundary as `@testable` symbols. These helpers run the full encode/decode
    // crossing here so tests can exercise every `ComplexValue` case (including the
    // int/bool/StringList/unsupported variant types that no on-disk format
    // persists via complex properties) without a file.

    /// Encode `maps`, cross into C++, and decode straight back. `.unsupported`
    /// fields carry nothing to serialize and are dropped.
    static func complexRoundTripForTesting(
        _ maps: [[String: ComplexValue]]
    ) -> [[String: ComplexValue]] {
        let builder = encodeComplex(maps)
        return decodeComplex(TagLibInterop.complexPropertiesRoundtrip(builder))
    }

    /// Decode a C++ sample whose only field is a `Double` — a variant type
    /// `ComplexValue` does not model — to verify it surfaces as `.unsupported`.
    static func decodeUnsupportedSampleForTesting() -> [[String: ComplexValue]] {
        decodeComplex(TagLibInterop.complexPropertyUnsupportedSample())
    }

    // MARK: - Cover art (complex property "PICTURE")

    /// Embedded pictures (cover art) as ``Picture`` values, layered over the
    /// generic ``complexProperties(_:)`` under the `"PICTURE"` key.
    ///
    /// Setting replaces the whole list; call ``save()`` to persist.
    public var pictures: [Picture] {
        get { complexProperties("PICTURE").map(Picture.init(complexMap:)) }
        set { setPictures(newValue) }
    }

    /// Replace all embedded pictures with `pictures`. Call ``save()`` to persist.
    @discardableResult
    public func setPictures(_ pictures: [Picture]) -> Bool {
        setComplexProperties("PICTURE", pictures.map(\.complexMap))
    }
}
