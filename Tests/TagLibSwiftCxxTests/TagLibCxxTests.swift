import XCTest
@testable import TagLibSwiftCxx

final class TagLibCxxTests: XCTestCase {
    var testFilePath: String!

    override func setUp() {
        super.setUp()
        guard let url = Bundle.module.url(forResource: "test", withExtension: "mp3") else {
            XCTFail("Test file not found")
            return
        }
        testFilePath = url.path
    }

    override func tearDown() {
        testFilePath = nil
        super.tearDown()
    }

    // Slice 1: AudioProperties bitrate + length (ms) via FileRef::audioProperties()
    func testAudioProperties() throws {
        let info = try XCTUnwrap(TagLibCxx.audioProperties(path: testFilePath))
        // test.mp3 is a ~1s mono file; exact values vary by encoder but must be sane.
        XCTAssertGreaterThan(info.bitrate, 0, "bitrate should be positive")
        XCTAssertGreaterThan(info.lengthMs, 0, "length should be positive")
        XCTAssertLessThan(info.lengthMs, 5000, "length should be roughly 1s")
    }

    // Slice 2: TagLib::String (tag->title()) -> Swift String
    func testTitleStringConversion() throws {
        let title = try XCTUnwrap(TagLibCxx.title(path: testFilePath))
        XCTAssertEqual(title, "Original Title")
    }

    // Slice 3: ID3v2 frame list (List<T> + format-specific MPEG::File / ID3v2::Tag)
    func testID3v2FrameListNonEmpty() throws {
        let count = try XCTUnwrap(TagLibCxx.id3v2FrameCount(path: testFilePath))
        XCTAssertGreaterThan(count, 0, "ID3v2 frame list should be non-empty")
    }

    func testInvalidPathReturnsNil() {
        XCTAssertNil(TagLibCxx.audioProperties(path: "/nonexistent/file.mp3"))
        XCTAssertNil(TagLibCxx.title(path: "/nonexistent/file.mp3"))
    }

    // MARK: - AudioFile: high-level SDK layer

    /// Copies the shared fixture to a unique temp file so write tests never
    /// mutate the bundle resource. Caller is responsible for cleanup.
    private func makeTempCopy() throws -> String {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiofile-\(UUID().uuidString).mp3")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: testFilePath), to: tempURL)
        return tempURL.path
    }

    func testAudioFileInvalidPathReturnsNil() {
        XCTAssertNil(AudioFile(path: "/nonexistent/file.mp3"))
    }

    func testBaseTagRead() throws {
        let file = try XCTUnwrap(AudioFile(path: testFilePath))
        XCTAssertTrue(file.isValid)
        XCTAssertEqual(file.title, "Original Title")
        XCTAssertEqual(file.artist, "Original Artist")
        XCTAssertEqual(file.album, "Original Album")
        XCTAssertEqual(file.genre, "Original Genre")
        XCTAssertEqual(file.year, 2023)
        XCTAssertEqual(file.track, 1)
        // comment was missing from the old bridge; here it reads (empty for the
        // fixture, but the accessor must exist and not crash).
        _ = file.comment
    }

    func testAudioPropertiesRead() throws {
        let file = try XCTUnwrap(AudioFile(path: testFilePath))
        XCTAssertEqual(file.bitrate.map { $0 > 0 }, true)
        let lengthMs = try XCTUnwrap(file.lengthInMilliseconds)
        XCTAssertGreaterThan(lengthMs, 500)
        XCTAssertLessThan(lengthMs, 2000, "test.mp3 is ~1s")
        XCTAssertEqual(file.sampleRate, 44100)
        XCTAssertEqual(file.channels, 1)
    }

    func testBaseTagWriteRoundtrip() throws {
        let path = try makeTempCopy()
        defer { try? FileManager.default.removeItem(atPath: path) }

        do {
            let file = try XCTUnwrap(AudioFile(path: path))
            file.title = "New Title"
            file.artist = "New Artist"
            file.album = "New Album"
            file.comment = "New Comment"
            file.genre = "New Genre"
            file.year = 1999
            file.track = 7
            try file.save()
        }

        let reopened = try XCTUnwrap(AudioFile(path: path))
        XCTAssertEqual(reopened.title, "New Title")
        XCTAssertEqual(reopened.artist, "New Artist")
        XCTAssertEqual(reopened.album, "New Album")
        XCTAssertEqual(reopened.comment, "New Comment")
        XCTAssertEqual(reopened.genre, "New Genre")
        XCTAssertEqual(reopened.year, 1999)
        XCTAssertEqual(reopened.track, 7)
    }

    func testPropertyMapRead() throws {
        let file = try XCTUnwrap(AudioFile(path: testFilePath))
        let props = file.properties
        XCTAssertFalse(props.isEmpty, "PropertyMap should expose the existing text tags")
        // The fixture's TITLE tag should surface through the universal map.
        XCTAssertEqual(props["TITLE"], ["Original Title"])
    }

    func testPropertyMapWriteRoundtrip() throws {
        let path = try makeTempCopy()
        defer { try? FileManager.default.removeItem(atPath: path) }

        do {
            let file = try XCTUnwrap(AudioFile(path: path))
            var props = file.properties
            props["COMPOSER"] = ["Jane Doe"]
            file.properties = props
            try file.save()
        }

        let reopened = try XCTUnwrap(AudioFile(path: path))
        XCTAssertEqual(reopened.properties["COMPOSER"], ["Jane Doe"])
    }
}
