import XCTest
@testable import TagLibSwift

final class TagFileTests: XCTestCase {
    var testFileURL: URL!
    var testFilePath: String!
    
    override func setUp() {
        super.setUp()
        // 테스트용 임시 MP3 파일 생성
        let bundle = Bundle.module
        guard let testFileURL = bundle.url(forResource: "test", withExtension: "mp3") else {
            XCTFail("Test file not found")
            return
        }
        self.testFileURL = testFileURL
        self.testFilePath = testFileURL.path
    }
    
    override func tearDown() {
        testFileURL = nil
        testFilePath = nil
        super.tearDown()
    }
    
    func testFileOpen() {
        XCTAssertNoThrow(try TagFile(path: testFilePath))
    }
    
    func testFileOpenFailure() {
        XCTAssertThrowsError(try TagFile(path: "/nonexistent/file.mp3")) { error in
            XCTAssertEqual(error as? TagLibError, .fileOpenFailed)
        }
    }
    
    func testMetadataRead() throws {
        let file = try TagFile(path: testFilePath)
        
        // 기본 메타데이터 읽기 테스트
        XCTAssertNotNil(file.title)
        XCTAssertNotNil(file.artist)
        XCTAssertNotNil(file.album)
        XCTAssertNotNil(file.genre)
        XCTAssertNotNil(file.year)
        XCTAssertNotNil(file.track)
    }
    
    func testMetadataWrite() throws {
        let file = try TagFile(path: testFilePath)
        
        // 메타데이터 수정
        let newTitle = "Test Title"
        let newArtist = "Test Artist"
        let newAlbum = "Test Album"
        let newGenre = "Test Genre"
        let newYear: UInt = 2024
        let newTrack: UInt = 1
        
        file.title = newTitle
        file.artist = newArtist
        file.album = newAlbum
        file.genre = newGenre
        file.year = newYear
        file.track = newTrack
        
        // 변경사항 저장
        XCTAssertNoThrow(try file.save())
        
        // 새로운 파일 인스턴스로 변경사항 확인
        let newFile = try TagFile(path: testFilePath)
        XCTAssertEqual(newFile.title, newTitle)
        XCTAssertEqual(newFile.artist, newArtist)
        XCTAssertEqual(newFile.album, newAlbum)
        XCTAssertEqual(newFile.genre, newGenre)
        XCTAssertEqual(newFile.year, newYear)
        XCTAssertEqual(newFile.track, newTrack)
    }
    
    func testSaveFailure() throws {
        let file = try TagFile(path: testFilePath)
        
        // 읽기 전용 파일로 변경
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: testFilePath)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: testFilePath)
        }
        
        // 저장 실패 테스트
        XCTAssertThrowsError(try file.save()) { error in
            XCTAssertEqual(error as? TagLibError, .saveFailed)
        }
    }
} 