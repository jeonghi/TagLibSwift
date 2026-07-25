import CTagLibCore
import CxxStdlib

/// Thin Swift surface over TagLib's C++ API, exercised via Swift/C++ interop.
///
/// Phase 1 spike: the three functions below prove the three representative
/// slices are reachable. TagLib's abstract base classes (AudioProperties, Tag)
/// are not importable by raw interop, so the small inline C++ helpers in
/// `taglib_interop.h` (namespace `TagLibInterop`) bridge those gaps while still
/// trafficking in TagLib C++ value types.
public enum TagLibCxx {

    // MARK: - Slice 1: AudioProperties (bitrate + length ms)

    public struct AudioInfo: Equatable {
        public let bitrate: Int
        public let lengthMs: Int
    }

    public static func audioProperties(path: String) -> AudioInfo? {
        path.withCString { cstr in
            let ref = TagLibInterop.openFile(cstr)
            if ref.isNull() { return nil }
            return AudioInfo(
                bitrate: Int(TagLibInterop.bitrate(ref)),
                lengthMs: Int(TagLibInterop.lengthInMilliseconds(ref))
            )
        }
    }

    // MARK: - Slice 2: TagLib::String -> Swift String

    public static func title(path: String) -> String? {
        path.withCString { cstr in
            let ref = TagLibInterop.openFile(cstr)
            if ref.isNull() { return nil }
            // TagLibInterop.title returns a TagLib::String value; convert it to a
            // Swift String here to prove the container bridges cleanly. to8Bit(true)
            // yields a std::string (an independent value) that CxxStdlib maps to
            // Swift.String.
            // TagLibInterop.title returns a std::string (UTF-8) that CxxStdlib
            // bridges to Swift.String cleanly.
            return String(TagLibInterop.title(ref))
        }
    }

    // MARK: - Slice 3: ID3v2 frame list (List<T> + format-specific class)

    public static func id3v2FrameCount(path: String) -> Int? {
        path.withCString { cstr in
            // Returns a copy of List<Frame*>; we only read its metadata.
            let frames = TagLibInterop.id3v2FrameList(cstr)
            return Int(frames.size())
        }
    }
}
