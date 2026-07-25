/// Read-only audio characteristics of a file, mirroring TagLib's
/// `AudioProperties` (the abstract base whose concrete values are read on the
/// C++ side). Obtained from ``AudioFile/audioProperties``.
///
/// A plain value type — no imported C++ reference types — so the package's
/// iOS 13 / macOS 10.15 deployment floor is preserved.
public struct AudioProperties: Equatable {

    /// MPEG audio version, for MPEG streams (from `MPEG::Properties::version()`).
    public enum MPEGVersion: Int, Equatable {
        case version1 = 0
        case version2 = 1
        case version2_5 = 2
        case version4 = 3
    }

    /// Length of the audio in whole seconds.
    public let lengthInSeconds: Int
    /// Length of the audio in milliseconds.
    public let lengthInMilliseconds: Int
    /// Bitrate in kbps.
    public let bitrate: Int
    /// Sample rate in Hz.
    public let sampleRate: Int
    /// Number of audio channels.
    public let channels: Int

    /// Bits per sample, for formats that carry it (FLAC, WAV, AIFF, MP4, APE,
    /// WavPack, TrueAudio, DSF, DSDIFF). `nil` for MPEG/Vorbis/Opus and others
    /// with no such concept.
    public let bitsPerSample: Int?
    /// MPEG version, or `nil` for non-MPEG streams.
    public let mpegVersion: MPEGVersion?
    /// MPEG layer (1–3), or `nil` for non-MPEG streams.
    public let mpegLayer: Int?

    public init(
        lengthInSeconds: Int,
        lengthInMilliseconds: Int,
        bitrate: Int,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int? = nil,
        mpegVersion: MPEGVersion? = nil,
        mpegLayer: Int? = nil
    ) {
        self.lengthInSeconds = lengthInSeconds
        self.lengthInMilliseconds = lengthInMilliseconds
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.mpegVersion = mpegVersion
        self.mpegLayer = mpegLayer
    }
}
