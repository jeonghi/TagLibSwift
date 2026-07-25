import CTagLibCore
import CxxStdlib

/// The common, format-independent metadata fields of an audio file, mirroring
/// TagLib's abstract `Tag` (title / artist / album / comment / genre / year /
/// track). Obtained from ``AudioFile/tag``.
///
/// Like TagLib, this is a live view onto the file: setting a property mutates
/// the underlying tag in place, and the change is persisted by calling
/// ``AudioFile/save()``. `Tag` is a lightweight value that retains its
/// ``AudioFile``; the setters are `nonmutating` because the mutation lands on
/// the shared file, not on the `Tag` value itself.
public struct Tag {
    private let file: AudioFile

    init(file: AudioFile) {
        self.file = file
    }

    public var title: String {
        get { String(TagLibInterop.title(file.fileRef)) }
        nonmutating set { newValue.withCString { TagLibInterop.setTitle(&file.fileRef, $0) } }
    }

    public var artist: String {
        get { String(TagLibInterop.artist(file.fileRef)) }
        nonmutating set { newValue.withCString { TagLibInterop.setArtist(&file.fileRef, $0) } }
    }

    public var album: String {
        get { String(TagLibInterop.album(file.fileRef)) }
        nonmutating set { newValue.withCString { TagLibInterop.setAlbum(&file.fileRef, $0) } }
    }

    public var comment: String {
        get { String(TagLibInterop.comment(file.fileRef)) }
        nonmutating set { newValue.withCString { TagLibInterop.setComment(&file.fileRef, $0) } }
    }

    public var genre: String {
        get { String(TagLibInterop.genre(file.fileRef)) }
        nonmutating set { newValue.withCString { TagLibInterop.setGenre(&file.fileRef, $0) } }
    }

    public var year: UInt {
        get { UInt(TagLibInterop.year(file.fileRef)) }
        nonmutating set { TagLibInterop.setYear(&file.fileRef, UInt32(newValue)) }
    }

    public var track: UInt {
        get { UInt(TagLibInterop.track(file.fileRef)) }
        nonmutating set { TagLibInterop.setTrack(&file.fileRef, UInt32(newValue)) }
    }

    /// Whether every field is empty (all strings empty and year/track zero),
    /// mirroring TagLib's `Tag::isEmpty`.
    public var isEmpty: Bool {
        title.isEmpty && artist.isEmpty && album.isEmpty
            && comment.isEmpty && genre.isEmpty && year == 0 && track == 0
    }
}
