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
}
