import Foundation

/// A piece of embedded cover art (or other attached picture) on an audio file.
///
/// Maps TagLib's complex-property `"PICTURE"` `VariantMap`: `data` (the raw
/// image bytes), `mimeType` (e.g. `"image/png"`), a free-text `description`,
/// and a `pictureType` describing the image's role (front cover, back cover,
/// artist, ...).
///
/// A plain value type — no imported C++ reference types — so the package's
/// iOS 13 / macOS 10.15 deployment floor is preserved.
public struct Picture: Equatable {

    /// The role of an attached picture. Raw values match the ID3v2 APIC /
    /// FLAC picture type strings TagLib uses in the `"pictureType"` field.
    public enum PictureType: String, Equatable {
        case other = "Other"
        case fileIcon = "File icon"
        case otherFileIcon = "Other file icon"
        case frontCover = "Front Cover"
        case backCover = "Back Cover"
        case leafletPage = "Leaflet page"
        case media = "Media"
        case leadArtist = "Lead artist"
        case artist = "Artist"
        case conductor = "Conductor"
        case band = "Band"
        case composer = "Composer"
        case lyricist = "Lyricist"
        case recordingLocation = "Recording location"
        case duringRecording = "During recording"
        case duringPerformance = "During performance"
        case movieScreenCapture = "Movie screen capture"
        case colouredFish = "Coloured fish"
        case illustration = "Illustration"
        case bandLogo = "Band logo"
        case publisherLogo = "Publisher logo"
    }

    /// Raw image bytes.
    public var data: Data
    /// MIME type of `data`, e.g. `"image/png"` or `"image/jpeg"`.
    public var mimeType: String
    /// Free-text description of the picture (often empty).
    public var description: String
    /// The picture's role. Defaults to ``PictureType/frontCover``.
    public var pictureType: PictureType

    public init(
        data: Data,
        mimeType: String,
        description: String = "",
        pictureType: PictureType = .frontCover
    ) {
        self.data = data
        self.mimeType = mimeType
        self.description = description
        self.pictureType = pictureType
    }
}
