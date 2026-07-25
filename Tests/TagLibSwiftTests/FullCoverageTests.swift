import XCTest
import CTagLibCore
import CxxStdlib
@testable import TagLibSwift

/// Tests for the promoted API: in-memory I/O, generic complex properties, and
/// extended audio properties.
final class FullCoverageTests: XCTestCase {

    private var mp3Data: Data!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "test", withExtension: "mp3"))
        mp3Data = try Data(contentsOf: url)
    }

    override func tearDown() {
        mp3Data = nil
        super.tearDown()
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

    // MARK: - In-memory I/O

    func testOpenFromMemoryReadsTagsAndAudioProperties() throws {
        let file = try XCTUnwrap(AudioFile(data: mp3Data, fileExtension: "mp3"))
        XCTAssertTrue(file.isValid)
        XCTAssertFalse(file.isNull)
        XCTAssertEqual(file.tag.title, "Original Title")
        XCTAssertEqual(file.tag.artist, "Original Artist")
        let audio = try XCTUnwrap(file.audioProperties)
        XCTAssertEqual(audio.sampleRate, 44100)
        XCTAssertGreaterThan(audio.bitrate, 0)
    }

    /// Bytes that resolve to no format — neither by the (unknown) extension nor by
    /// content sniffing — yield a null ref, so the initializer returns nil.
    func testInvalidBytesReturnNil() {
        XCTAssertNil(AudioFile(data: Data([0x00, 0x01, 0x02, 0x03]), fileExtension: "xyz"))
    }

    func testEmptyDataReturnsNil() {
        XCTAssertNil(AudioFile(data: Data(), fileExtension: "xyz"))
    }

    /// Edit a tag on a memory file, save (writes back into the stream), read the
    /// bytes with serialized(), reopen from memory, and assert the edit persisted.
    func testInMemoryEditSaveSerializeRoundtrip() throws {
        let file = try XCTUnwrap(AudioFile(data: mp3Data, fileExtension: "mp3"))
        file.tag.title = "Memory Title"
        file.tag.artist = "Memory Artist"
        var props = file.properties
        props["COMPOSER"] = ["In-Memory Composer"]
        file.properties = props
        try file.save()

        let serialized = try file.serialized()
        XCTAssertGreaterThan(serialized.count, 0)
        XCTAssertNotEqual(serialized, mp3Data, "edited bytes should differ from the original")

        let reopened = try XCTUnwrap(AudioFile(data: serialized, fileExtension: "mp3"))
        XCTAssertEqual(reopened.tag.title, "Memory Title")
        XCTAssertEqual(reopened.tag.artist, "Memory Artist")
        XCTAssertEqual(reopened.properties["COMPOSER"], ["In-Memory Composer"])
    }

    /// serialized() on a path-backed file has no in-memory buffer and must throw.
    func testSerializedThrowsForPathBackedFile() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "test", withExtension: "mp3"))
        let file = try XCTUnwrap(AudioFile(path: url.path))
        XCTAssertThrowsError(try file.serialized()) { error in
            XCTAssertEqual(error as? AudioFileError, .notMemoryBacked)
        }
    }

    // MARK: - Extended audio properties

    /// MP3 (MPEG) has no bits-per-sample, but does report version and layer.
    func testExtendedAudioPropertiesMP3() throws {
        let file = try XCTUnwrap(AudioFile(data: mp3Data, fileExtension: "mp3"))
        let audio = try XCTUnwrap(file.audioProperties)
        XCTAssertNil(audio.bitsPerSample, "MPEG carries no bits-per-sample")
        XCTAssertNotNil(audio.mpegVersion, "MPEG version should be present")
        XCTAssertEqual(audio.mpegLayer, 3, "test.mp3 is MPEG Layer III")
    }

    /// FLAC reports bits-per-sample and has no MPEG version/layer. Requires ffmpeg;
    /// skipped cleanly otherwise.
    func testExtendedAudioPropertiesFLAC() throws {
        let path = try Self.makeFLACFixture()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = try XCTUnwrap(AudioFile(path: path))
        let audio = try XCTUnwrap(file.audioProperties)
        XCTAssertNotNil(audio.bitsPerSample, "FLAC reports bits-per-sample")
        XCTAssertGreaterThan(try XCTUnwrap(audio.bitsPerSample), 0)
        XCTAssertNil(audio.mpegVersion, "FLAC is not MPEG")
        XCTAssertNil(audio.mpegLayer, "FLAC is not MPEG")
    }

    // MARK: - Generic complex properties

    /// A file with cover art exposes "PICTURE" among its complex-property keys,
    /// and complexProperties("PICTURE") round-trips the string + data fields.
    func testComplexPropertyKeysAndPictureFields() throws {
        let file = try XCTUnwrap(AudioFile(data: mp3Data, fileExtension: "mp3"))
        XCTAssertFalse(file.complexPropertyKeys.contains("PICTURE"),
                       "fixture starts with no cover art")

        file.setPictures([
            Picture(data: Data(Self.pngBytes), mimeType: "image/png",
                    description: "cover", pictureType: .frontCover)
        ])
        try file.save()

        let serialized = try file.serialized()
        let reopened = try XCTUnwrap(AudioFile(data: serialized, fileExtension: "mp3"))
        XCTAssertTrue(reopened.complexPropertyKeys.contains("PICTURE"))

        let maps = reopened.complexProperties("PICTURE")
        XCTAssertEqual(maps.count, 1)
        let map = try XCTUnwrap(maps.first)
        XCTAssertEqual(map["data"], .data(Data(Self.pngBytes)))
        XCTAssertEqual(map["mimeType"], .string("image/png"))
        XCTAssertEqual(map["description"], .string("cover"))
        XCTAssertEqual(map["pictureType"], .string("Front Cover"))
    }

    /// setComplexProperties on a null / unsupported key returns false rather than
    /// crashing (exercises the applyComplexProperties null/false path).
    func testSetComplexPropertiesRejectsUnknownKey() throws {
        let file = try XCTUnwrap(AudioFile(data: mp3Data, fileExtension: "mp3"))
        let accepted = file.setComplexProperties("NOT_A_REAL_KEY", [["x": .string("y")]])
        XCTAssertFalse(accepted, "an unknown complex-property key must not be accepted")
    }

    /// Every ComplexValue case survives the encode -> C++ crossing -> decode
    /// round-trip. Uses the direct crossing helper so int/bool/StringList are
    /// exercised even though no format persists them via complex properties.
    /// `.unsupported` carries nothing to serialize, so it is dropped on encode.
    func testComplexValueRoundtripAllTypes() throws {
        let input: [[String: ComplexValue]] = [[
            "s": .string("héllo"),
            "i": .int(-42),
            "b": .bool(true),
            "d": .data(Data([0x00, 0xFF, 0x10])),
            "l": .stringList(["one", "two", "three"]),
            "u": .unsupported
        ]]
        let output = AudioFile.complexRoundTripForTesting(input)

        XCTAssertEqual(output.count, 1)
        var expected = input[0]
        expected["u"] = nil // .unsupported is not serialized
        XCTAssertEqual(output.first, expected)
    }

    /// A Variant type ComplexValue does not model (Double) decodes to .unsupported.
    func testUnsupportedVariantDecodesAsUnsupported() {
        let output = AudioFile.decodeUnsupportedSampleForTesting()
        XCTAssertEqual(output.first?["dbl"], .unsupported)
    }

    /// An empty file exposes no complex-property keys (null-safe path).
    func testComplexPropertyKeysEmptyForBareFixture() throws {
        let file = try XCTUnwrap(AudioFile(data: mp3Data, fileExtension: "mp3"))
        XCTAssertTrue(file.complexPropertyKeys.isEmpty)
    }

    // MARK: - Helpers

    private static func makeFLACFixture() throws -> String {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let ffmpeg = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            throw XCTSkip("ffmpeg not found; skipping FLAC extended-properties test")
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("fullcov-\(UUID().uuidString).flac")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "1",
            "-c:a", "flac", out.path
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: out.path) else {
            throw XCTSkip("ffmpeg could not produce FLAC")
        }
        return out.path
    }
}
