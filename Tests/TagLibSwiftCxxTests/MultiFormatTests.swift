import XCTest
@testable import TagLibSwiftCxx

/// Smoke tests across several container formats (FLAC, MP4/M4A, Ogg Vorbis).
///
/// Fixtures are generated at runtime with `ffmpeg` into a temp directory, so
/// nothing needs to be committed and the tests never mutate a shared file. If
/// `ffmpeg` (or a required encoder) is unavailable, the affected test is skipped
/// with a clear message via `XCTSkip` rather than failing.
final class MultiFormatTests: XCTestCase {

    private static let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("taglib-multiformat-\(UUID().uuidString)")

    /// Cached ffmpeg path (searched once), or nil if ffmpeg is not installed.
    private static let ffmpegPath: String? = {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        // Fall back to `which ffmpeg`.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "ffmpeg"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        do {
            try which.run()
            which.waitUntilExit()
            guard which.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }()

    override class func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
    }

    override class func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Generate a ~1s clip in `format` with title/artist metadata. Returns the
    /// path, or throws `XCTSkip` if ffmpeg/the encoder isn't available.
    private func makeFixture(ext: String, codec: String) throws -> String {
        guard let ffmpeg = Self.ffmpegPath else {
            throw XCTSkip("ffmpeg not found; skipping \(ext) smoke test")
        }
        let outURL = Self.tempDir.appendingPathComponent("test-\(UUID().uuidString).\(ext)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "1",
            "-c:a", codec,
            "-metadata", "title=Original Title",
            "-metadata", "artist=Original Artist",
            "-metadata", "album=Original Album",
            outURL.path
        ]
        process.standardOutput = Pipe()
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outURL.path) else {
            let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             as: UTF8.self)
            throw XCTSkip("ffmpeg could not produce \(ext) (encoder \(codec) missing?): \(err)")
        }
        return outURL.path
    }

    /// Full smoke check for one format: base tag read, audio properties, and a
    /// PropertyMap write+save roundtrip.
    private func runSmokeTest(ext: String, codec: String) throws {
        let path = try makeFixture(ext: ext, codec: codec)
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Base tag read.
        let file = try XCTUnwrap(AudioFile(path: path), "AudioFile failed to open \(ext)")
        XCTAssertTrue(file.isValid, "\(ext) should parse")
        XCTAssertEqual(file.title, "Original Title", "\(ext) title")
        XCTAssertEqual(file.artist, "Original Artist", "\(ext) artist")

        // Audio properties.
        let bitrate = try XCTUnwrap(file.bitrate, "\(ext) bitrate")
        XCTAssertGreaterThan(bitrate, 0, "\(ext) bitrate > 0")
        let lengthMs = try XCTUnwrap(file.lengthInMilliseconds, "\(ext) length")
        XCTAssertGreaterThan(lengthMs, 0, "\(ext) length > 0")

        // PropertyMap read.
        XCTAssertFalse(file.properties.isEmpty, "\(ext) PropertyMap non-empty")

        // PropertyMap write + save + reopen roundtrip.
        var props = file.properties
        props["COMPOSER"] = ["Jane Doe"]
        file.properties = props
        try file.save()

        let reopened = try XCTUnwrap(AudioFile(path: path))
        XCTAssertEqual(reopened.properties["COMPOSER"], ["Jane Doe"],
                       "\(ext) PropertyMap write should persist")
    }

    func testFLAC() throws {
        try runSmokeTest(ext: "flac", codec: "flac")
    }

    func testM4A() throws {
        try runSmokeTest(ext: "m4a", codec: "aac")
    }

    func testOggVorbis() throws {
        try runSmokeTest(ext: "ogg", codec: "libvorbis")
    }

    /// `setProperties` must report the keys the format could not store. MP4/M4A's
    /// property interface rejects a key that TagLib cannot map to an item name —
    /// e.g. a key whose first character is not A-Z (PropertyMap upcases keys, so a
    /// leading digit stays invalid). The rejected key must come back in the
    /// returned unsupported map (empty would be silent data loss reported as OK).
    func testSetPropertiesReportsRejectedKeyM4A() throws {
        let path = try makeFixture(ext: "m4a", codec: "aac")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let file = try XCTUnwrap(AudioFile(path: path), "AudioFile failed to open m4a")
        let rejectedKey = "2LEADINGDIGIT"
        let unsupported = file.setProperties([
            "TITLE": ["Accepted"],
            rejectedKey: ["should be rejected"]
        ])
        XCTAssertFalse(unsupported.isEmpty,
                       "MP4 cannot store \(rejectedKey); unsupported map must be non-empty")
        XCTAssertEqual(unsupported[rejectedKey], ["should be rejected"],
                       "the rejected key must be named in the unsupported map")
        XCTAssertNil(unsupported["TITLE"], "accepted keys must not appear as unsupported")
    }

    /// A tiny valid 1x1 PNG — realistic non-trivial cover-art payload.
    private static let pngBytes: [UInt8] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82
    ]

    /// Cover-art set->save->read roundtrip on a SECOND format (FLAC), which stores
    /// pictures via the `PICTURE` complex property. Asserts bytes + mimeType
    /// roundtrip exactly, broadening cover-art coverage beyond MP3/ID3v2.
    func testCoverArtRoundtripFLAC() throws {
        let path = try makeFixture(ext: "flac", codec: "flac")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let imageData = Data(Self.pngBytes)
        do {
            let file = try XCTUnwrap(AudioFile(path: path), "AudioFile failed to open flac")
            XCTAssertTrue(file.pictures.isEmpty, "fresh FLAC fixture has no cover art")
            file.setPictures([
                Picture(data: imageData, mimeType: "image/png",
                        description: "cover", pictureType: .frontCover)
            ])
            try file.save()
        }

        let reopened = try XCTUnwrap(AudioFile(path: path))
        let pictures = reopened.pictures
        XCTAssertEqual(pictures.count, 1, "FLAC should persist exactly one picture")
        let picture = try XCTUnwrap(pictures.first)
        XCTAssertEqual(picture.data, imageData, "FLAC picture bytes must roundtrip exactly")
        XCTAssertEqual(picture.mimeType, "image/png", "FLAC picture mimeType must roundtrip")
    }
}
