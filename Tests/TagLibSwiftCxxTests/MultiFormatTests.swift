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
}
