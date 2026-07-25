import CTagLibCore
import CxxStdlib

/// Errors thrown by ``AudioFile``.
public enum AudioFileError: Error, Equatable {
    /// Persisting tag changes to disk failed.
    case saveFailed
}

/// A high-level, ergonomic handle to an audio file's metadata, layered over
/// TagLib's C++ API via Swift/C++ interop.
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
    public var fileRef: TagLib.FileRef

    /// Open the file at `path`. Returns `nil` if TagLib could not parse it.
    public init?(path: String) {
        let ref = path.withCString { TagLibInterop.openFile($0) }
        if ref.isNull() { return nil }
        self.fileRef = ref
    }

    /// Whether the underlying file was parsed successfully.
    public var isValid: Bool {
        TagLibInterop.isValid(fileRef)
    }

    /// Persist pending tag changes to disk.
    /// - Throws: ``AudioFileError/saveFailed`` if TagLib reported a write failure.
    public func save() throws {
        if !TagLibInterop.save(&fileRef) {
            throw AudioFileError.saveFailed
        }
    }

    // MARK: - Base tag (get/set)

    public var title: String {
        get { String(TagLibInterop.title(fileRef)) }
        set { newValue.withCString { TagLibInterop.setTitle(&fileRef, $0) } }
    }

    public var artist: String {
        get { String(TagLibInterop.artist(fileRef)) }
        set { newValue.withCString { TagLibInterop.setArtist(&fileRef, $0) } }
    }

    public var album: String {
        get { String(TagLibInterop.album(fileRef)) }
        set { newValue.withCString { TagLibInterop.setAlbum(&fileRef, $0) } }
    }

    public var comment: String {
        get { String(TagLibInterop.comment(fileRef)) }
        set { newValue.withCString { TagLibInterop.setComment(&fileRef, $0) } }
    }

    public var genre: String {
        get { String(TagLibInterop.genre(fileRef)) }
        set { newValue.withCString { TagLibInterop.setGenre(&fileRef, $0) } }
    }

    public var year: UInt {
        get { UInt(TagLibInterop.year(fileRef)) }
        set { TagLibInterop.setYear(&fileRef, UInt32(newValue)) }
    }

    public var track: UInt {
        get { UInt(TagLibInterop.track(fileRef)) }
        set { TagLibInterop.setTrack(&fileRef, UInt32(newValue)) }
    }

    // MARK: - Audio properties (read-only)

    /// Length in whole seconds, or `nil` if unavailable.
    public var lengthInSeconds: Int? { nonNegative(TagLibInterop.lengthInSeconds(fileRef)) }

    /// Length in milliseconds, or `nil` if unavailable.
    public var lengthInMilliseconds: Int? { nonNegative(TagLibInterop.lengthInMilliseconds(fileRef)) }

    /// Bitrate in kbps, or `nil` if unavailable.
    public var bitrate: Int? { nonNegative(TagLibInterop.bitrate(fileRef)) }

    /// Sample rate in Hz, or `nil` if unavailable.
    public var sampleRate: Int? { nonNegative(TagLibInterop.sampleRate(fileRef)) }

    /// Channel count, or `nil` if unavailable.
    public var channels: Int? { nonNegative(TagLibInterop.channels(fileRef)) }

    private func nonNegative(_ value: Int32) -> Int? {
        value < 0 ? nil : Int(value)
    }

    // MARK: - PropertyMap (the universal all-text-tags interface)

    /// All text tags as a format-independent map (`TagLib::PropertyMap`).
    ///
    /// Reading snapshots the file's current PropertyMap once on the C++ side and
    /// rebuilds it here via flat, index-addressed accessors. Writing replaces the
    /// tag's properties wholesale via `Tag::setProperties`; call ``save()`` to
    /// persist. Keys are format-independent (`ALBUMARTIST`, `COMPOSER`,
    /// `DISCNUMBER`, `BPM`, ...).
    public var properties: [String: [String]] {
        get {
            let access = TagLibInterop.PropertyMapAccess(fileRef)
            var result: [String: [String]] = [:]
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
    public func setProperties(_ props: [String: [String]]) {
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
        _ = TagLibInterop.applyProperties(&fileRef, builder)
    }
}
