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
        return AudioProperties(
            lengthInSeconds: Int(TagLibInterop.lengthInSeconds(fileRef)),
            lengthInMilliseconds: Int(TagLibInterop.lengthInMilliseconds(fileRef)),
            bitrate: Int(TagLibInterop.bitrate(fileRef)),
            sampleRate: Int(TagLibInterop.sampleRate(fileRef)),
            channels: Int(TagLibInterop.channels(fileRef))
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

    // MARK: - Cover art (complex property "PICTURE")

    /// Embedded pictures (cover art) as ``Picture`` values, read from TagLib's
    /// `complexProperties("PICTURE")`.
    ///
    /// Reading snapshots the file's picture list once on the C++ side and
    /// rebuilds it here. Setting replaces the whole list via
    /// `setComplexProperties`; call ``save()`` to persist.
    public var pictures: [Picture] {
        get {
            let access = TagLibInterop.PictureListAccess(fileRef)
            var result: [Picture] = []
            let count = access.count()
            result.reserveCapacity(Int(count))
            var i: UInt32 = 0
            while i < count {
                let size = Int(access.pictureDataSize(i))
                var data = Data(count: size)
                if size > 0 {
                    data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                        if let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) {
                            access.copyPictureData(i, base)
                        }
                    }
                }
                // Unknown/empty pictureType strings map to `.other`, never a
                // fabricated `.frontCover` (that would distort meaning on a
                // set->save->read roundtrip).
                let type = Picture.PictureType.from(rawValue: String(access.pictureType(i)))
                result.append(
                    Picture(
                        data: data,
                        mimeType: String(access.mimeType(i)),
                        description: String(access.description(i)),
                        pictureType: type
                    )
                )
                i += 1
            }
            return result
        }
        set { setPictures(newValue) }
    }

    /// Replace all embedded pictures with `pictures`. Call ``save()`` to persist.
    public func setPictures(_ pictures: [Picture]) {
        var builder = TagLibInterop.PictureListBuilder()
        for picture in pictures {
            picture.description.withCString { descPtr in
                picture.mimeType.withCString { mimePtr in
                    picture.pictureType.rawValue.withCString { typePtr in
                        picture.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                            let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self)
                            builder.append(
                                base,
                                UInt32(picture.data.count),
                                mimePtr,
                                descPtr,
                                typePtr
                            )
                        }
                    }
                }
            }
        }
        // Free function, not a member method (see setProperties / applyProperties).
        _ = TagLibInterop.applyPictures(&fileRef, builder)
    }
}
