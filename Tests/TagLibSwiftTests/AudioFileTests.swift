import XCTest
import CTagLibCore
import CxxStdlib
@testable import TagLibSwift

/// Tests for the unified TagLib-faithful API: `AudioFile` → `tag` /
/// `audioProperties` / `properties` / `pictures` / `save`.
final class AudioFileTests: XCTestCase {
    var testFileURL: URL!
    var testFilePath: String!

    override func setUp() {
        super.setUp()
        guard let url = Bundle.module.url(forResource: "test", withExtension: "mp3") else {
            XCTFail("Test file not found")
            return
        }
        testFileURL = url
        testFilePath = url.path
    }

    override func tearDown() {
        testFileURL = nil
        testFilePath = nil
        super.tearDown()
    }

    /// Copies the shared fixture to a unique temp file so write tests never
    /// mutate the bundle resource. Caller is responsible for cleanup.
    private func makeTempCopy() throws -> String {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiofile-\(UUID().uuidString).mp3")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: testFilePath), to: tempURL)
        return tempURL.path
    }

    // MARK: - Open / validity

    func testOpenValidFile() throws {
        let file = try XCTUnwrap(AudioFile(path: testFilePath))
        XCTAssertTrue(file.isValid)
        // Mirrors TagLib::FileRef::isNull — always false for a live AudioFile.
        XCTAssertFalse(file.isNull)
    }

    func testInvalidPathReturnsNil() {
        XCTAssertNil(AudioFile(path: "/nonexistent/file.mp3"))
    }

    // MARK: - Base tag (read)

    func testBaseTagRead() throws {
        let file = try XCTUnwrap(AudioFile(path: testFilePath))
        let tag = file.tag
        XCTAssertEqual(tag.title, "Original Title")
        XCTAssertEqual(tag.artist, "Original Artist")
        XCTAssertEqual(tag.album, "Original Album")
        XCTAssertEqual(tag.genre, "Original Genre")
        XCTAssertEqual(tag.year, 2023)
        XCTAssertEqual(tag.track, 1)
        // comment was missing from the old bridge; here it reads (empty for the
        // fixture, but the accessor must exist and not crash).
        _ = tag.comment
        // The fixture carries real tags, so it is not empty.
        XCTAssertFalse(tag.isEmpty)
    }

    /// A tag with every field cleared reports `isEmpty == true`.
    func testTagIsEmptyWhenAllFieldsCleared() throws {
        let path = try makeTempCopy()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let file = try XCTUnwrap(AudioFile(path: path))
        let tag = file.tag
        tag.title = ""
        tag.artist = ""
        tag.album = ""
        tag.comment = ""
        tag.genre = ""
        tag.year = 0
        tag.track = 0
        XCTAssertTrue(tag.isEmpty)
    }

    // MARK: - Audio properties (read-only)

    func testAudioPropertiesRead() throws {
        let file = try XCTUnwrap(AudioFile(path: testFilePath))
        let props = try XCTUnwrap(file.audioProperties)
        XCTAssertGreaterThan(props.bitrate, 0)
        XCTAssertGreaterThan(props.lengthInMilliseconds, 500)
        XCTAssertLessThan(props.lengthInMilliseconds, 2000, "test.mp3 is ~1s")
        XCTAssertGreaterThan(props.lengthInSeconds, 0)
        XCTAssertEqual(props.sampleRate, 44100)
        XCTAssertEqual(props.channels, 1)
    }

    // MARK: - Base tag (write roundtrip)

    func testBaseTagWriteRoundtrip() throws {
        let path = try makeTempCopy()
        defer { try? FileManager.default.removeItem(atPath: path) }

        do {
            let file = try XCTUnwrap(AudioFile(path: path))
            let tag = file.tag
            tag.title = "New Title"
            tag.artist = "New Artist"
            tag.album = "New Album"
            tag.comment = "New Comment"
            tag.genre = "New Genre"
            tag.year = 1999
            tag.track = 7
            try file.save()
        }

        let reopened = try XCTUnwrap(AudioFile(path: path))
        let tag = reopened.tag
        XCTAssertEqual(tag.title, "New Title")
        XCTAssertEqual(tag.artist, "New Artist")
        XCTAssertEqual(tag.album, "New Album")
        XCTAssertEqual(tag.comment, "New Comment")
        XCTAssertEqual(tag.genre, "New Genre")
        XCTAssertEqual(tag.year, 1999)
        XCTAssertEqual(tag.track, 7)
    }

    // MARK: - PropertyMap

    func testPropertyMapRead() throws {
        let file = try XCTUnwrap(AudioFile(path: testFilePath))
        let props = file.properties
        XCTAssertFalse(props.isEmpty, "PropertyMap should expose the existing text tags")
        XCTAssertEqual(props["TITLE"], ["Original Title"])
    }

    func testPropertyMapWriteRoundtrip() throws {
        let path = try makeTempCopy()
        defer { try? FileManager.default.removeItem(atPath: path) }

        do {
            let file = try XCTUnwrap(AudioFile(path: path))
            var props = file.properties
            props["COMPOSER"] = ["Jane Doe"]
            // Exercises the `properties` computed-property SETTER.
            file.properties = props
            try file.save()
        }

        let reopened = try XCTUnwrap(AudioFile(path: path))
        XCTAssertEqual(reopened.properties["COMPOSER"], ["Jane Doe"])
    }

    /// Contract: `setProperties` returns the format's rejected/unsupported keys
    /// (empty means every key was stored). ID3v2 implements the complete
    /// PropertyMap interface, so a normal write of supported keys must report an
    /// EMPTY unsupported map — never silent partial data loss reported as success.
    func testSetPropertiesReturnsEmptyOnFullSuccess() throws {
        let path = try makeTempCopy()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let file = try XCTUnwrap(AudioFile(path: path))
        let unsupported = file.setProperties([
            "TITLE": ["A title"],
            "ARTIST": ["An artist"],
            "COMPOSER": ["Jane Doe"]
        ])
        XCTAssertTrue(unsupported.isEmpty,
                      "ID3v2 stores all these keys; unsupported map must be empty")
    }

    /// A key mapped to an empty array must record the key with zero values
    /// (via `PropertyMapBuilder::ensureKey`) rather than being skipped or
    /// crashing, and must not be treated as an unsupported/rejected key.
    func testSetPropertiesWithEmptyValuesRecordsKeyWithoutCrashing() throws {
        let path = try makeTempCopy()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let file = try XCTUnwrap(AudioFile(path: path))
        let unsupported = file.setProperties([
            "TITLE": ["A title"],
            "COMMENT": []
        ])
        XCTAssertNil(unsupported["COMMENT"], "an empty-values key is accepted, not rejected")
        try file.save()

        let reopened = try XCTUnwrap(AudioFile(path: path))
        XCTAssertEqual(reopened.properties["TITLE"], ["A title"])
    }

    // MARK: - Cover art (complex property "PICTURE")

    /// A tiny valid PNG (1x1). TagLib stores the picture bytes verbatim, so the
    /// exact image content is irrelevant to the roundtrip — this is just a
    /// realistic, non-trivial payload.
    private static let pngBytes: [UInt8] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, // IDAT chunk
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND chunk
        0x42, 0x60, 0x82
    ]

    func testCoverArtRoundtrip() throws {
        let path = try makeTempCopy()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let imageData = Data(Self.pngBytes)

        do {
            let file = try XCTUnwrap(AudioFile(path: path))
            XCTAssertTrue(file.pictures.isEmpty, "fixture starts with no cover art")
            let picture = Picture(
                data: imageData,
                mimeType: "image/png",
                description: "cover",
                pictureType: .frontCover
            )
            file.setPictures([picture])
            try file.save()
        }

        let reopened = try XCTUnwrap(AudioFile(path: path))
        let pictures = reopened.pictures
        XCTAssertEqual(pictures.count, 1)
        let picture = try XCTUnwrap(pictures.first)
        XCTAssertEqual(picture.data, imageData, "picture bytes must roundtrip exactly")
        XCTAssertEqual(picture.mimeType, "image/png")
        XCTAssertEqual(picture.description, "cover")
        XCTAssertEqual(picture.pictureType, .frontCover)
    }

    /// Exercises the `pictures` computed property's SETTER (`file.pictures =
    /// [...]`), not `setPictures(_:)` directly.
    func testPicturesPropertySetter() throws {
        let path = try makeTempCopy()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let imageData = Data(Self.pngBytes)
        do {
            let file = try XCTUnwrap(AudioFile(path: path))
            file.pictures = [
                Picture(data: imageData, mimeType: "image/png",
                        description: "via setter", pictureType: .frontCover)
            ]
            try file.save()
        }

        let reopened = try XCTUnwrap(AudioFile(path: path))
        let picture = try XCTUnwrap(reopened.pictures.first)
        XCTAssertEqual(picture.data, imageData)
        XCTAssertEqual(picture.description, "via setter")
    }

    /// Unknown/empty pictureType strings must map to `.other`, NEVER a fabricated
    /// `.frontCover`. (This is the exact regression: the read path previously did
    /// `PictureType(rawValue:) ?? .frontCover`. This test fails if that returns.)
    func testUnknownPictureTypeMapsToOtherNotFrontCover() {
        XCTAssertEqual(Picture.PictureType.from(rawValue: "Some Unlisted Type"), .other)
        XCTAssertEqual(Picture.PictureType.from(rawValue: ""), .other)
        XCTAssertNotEqual(Picture.PictureType.from(rawValue: "Some Unlisted Type"), .frontCover)
        // Known strings still map correctly.
        XCTAssertEqual(Picture.PictureType.from(rawValue: "Front Cover"), .frontCover)
        XCTAssertEqual(Picture.PictureType.from(rawValue: "Back Cover"), .backCover)
    }

    /// A picture whose type is `.other` must NOT be reported as `.frontCover`
    /// after a roundtrip. (Regression guard: the read path previously mapped any
    /// unknown/empty pictureType string to `.frontCover`, fabricating meaning;
    /// it now maps unknown strings to `.other` and roundtrips `.other` as `.other`.)
    func testCoverArtOtherTypeNotFabricatedAsFrontCover() throws {
        let path = try makeTempCopy()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let imageData = Data(Self.pngBytes)
        do {
            let file = try XCTUnwrap(AudioFile(path: path))
            file.setPictures([
                Picture(data: imageData, mimeType: "image/png",
                        description: "misc", pictureType: .other)
            ])
            try file.save()
        }

        let reopened = try XCTUnwrap(AudioFile(path: path))
        let picture = try XCTUnwrap(reopened.pictures.first)
        XCTAssertNotEqual(picture.pictureType, .frontCover,
                          "an `.other` picture must not roundtrip as `.frontCover`")
        XCTAssertEqual(picture.pictureType, .other,
                       "`.other` picture type must roundtrip as `.other`")
    }

    // MARK: - save() failure

    func testSaveFailure() throws {
        let path = try makeTempCopy()
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path)
            try? FileManager.default.removeItem(atPath: path)
        }
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)

        let file = try XCTUnwrap(AudioFile(path: path))
        file.tag.title = "New Title"

        XCTAssertThrowsError(try file.save()) { error in
            XCTAssertEqual(error as? AudioFileError, .saveFailed)
        }
    }

    // MARK: - String(taglib:) escape-hatch bridging

    /// The day-to-day API never surfaces a raw `TagLib::String` (the
    /// `TagLibInterop` helpers already return `std::string`, which CxxStdlib
    /// bridges to `Swift.String` directly). `String(taglib:)` exists for the
    /// raw escape hatch: any format-specific TagLib C++ API reached directly
    /// (e.g. via ``AudioFile/fileRef``) hands back this type, and this
    /// initializer decodes it as UTF-8.
    func testTaglibStringConversionViaRawEscapeHatch() throws {
        let rawTitle = TagLib.String("Original Title")
        XCTAssertEqual(String(taglib: rawTitle), "Original Title")
    }

    /// The `fileRef` escape hatch is reachable and points at the parsed file.
    func testFileRefEscapeHatch() throws {
        let file = try XCTUnwrap(AudioFile(path: testFilePath))
        XCTAssertFalse(file.fileRef.isNull())
    }
}
