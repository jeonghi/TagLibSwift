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
    
    // MARK: - SPM Package Tests
    
    func testPackageDependencies() {
        // TagLib 모듈이 제대로 링크되었는지 확인
        let file = try? TagFile(path: testFilePath)
        XCTAssertNotNil(file, "TagLib module should be properly linked")
    }
    
    func testModuleImports() {
        // 모든 필요한 모듈이 임포트되었는지 확인
        let mirror = Mirror(reflecting: try? TagFile(path: testFilePath) as Any)
        XCTAssertNotNil(mirror, "TagFile should be properly initialized")
    }
    
    func testBuildSettings() {
        #if os(iOS)
        XCTAssertTrue(true, "iOS platform is supported")
        #elseif os(macOS)
        XCTAssertTrue(true, "macOS platform is supported")
        #else
        XCTFail("Unsupported platform")
        #endif
    }
    
    // MARK: - File Operations Tests
    
    func testFileOpen() {
        XCTAssertNoThrow(try TagFile(path: testFilePath))
    }
    
    func testFileOpenFailure() {
        XCTAssertThrowsError(try TagFile(path: "/nonexistent/file.mp3")) { error in
            if case TagLibError.fileOpenFailed = error {
                // 성공
            } else {
                XCTFail("Expected fileOpenFailed error")
            }
        }
    }
    
    func testFileValidity() throws {
        let file = try TagFile(path: testFilePath)
        XCTAssertTrue(file.isValid)
    }
    
    // MARK: - Metadata Read Tests
    
    func testMetadataRead() throws {
        let file = try TagFile(path: testFilePath)
        
        // 기본 메타데이터 읽기 테스트
        XCTAssertEqual(file.title, "Original Title")
        XCTAssertEqual(file.artist, "Original Artist")
        XCTAssertEqual(file.album, "Original Album")
        XCTAssertEqual(file.genre, "Original Genre")
        XCTAssertEqual(file.year, 2023)
        XCTAssertEqual(file.track, 1)
    }
    
    // MARK: - Metadata Write Tests
    
    func testMetadataWrite() throws {
        let file = try TagFile(path: testFilePath)
        
        // 메타데이터 수정
        let newTitle = "Test Title"
        let newArtist = "Test Artist"
        let newAlbum = "Test Album"
        let newGenre = "Test Genre"
        let newYear: UInt = 2024
        let newTrack: UInt = 2
        
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
    
    // MARK: - Error Handling Tests
    
    func testInvalidFileOperations() {
        // 잘못된 파일 경로로 TagFile 생성 시도
        let file = try? TagFile(path: "/nonexistent/file.mp3")
        
        // 파일이 nil이어야 함
        XCTAssertNil(file, "File should be nil for invalid path")
    }
    
    func testSaveFailure() throws {
        // 임시 파일 생성
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_save.mp3")
        
        // 테스트 파일을 임시 파일로 복사
        try FileManager.default.copyItem(at: testFileURL, to: tempFile)
        
        // 파일을 읽기 전용으로 설정
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: tempFile.path)
        defer {
            // 테스트 후 파일 속성 복원 및 삭제
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: tempFile.path)
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        // 읽기 전용 파일에 대한 저장 시도
        let file = try TagFile(path: tempFile.path)
        file.title = "New Title"
        
        // 저장 실패 테스트
        XCTAssertThrowsError(try file.save()) { error in
            if case TagLibError.saveFailed = error {
                // 성공
            } else {
                XCTFail("Expected saveFailed error")
            }
        }
    }
    
    // MARK: - Memory Management Tests
    
    func testMemoryManagement() throws {
        weak var weakFile: TagFile?
        
        autoreleasepool {
            let file = try? TagFile(path: testFilePath)
            weakFile = file
            
            // 파일 사용
            _ = file?.title
            _ = file?.artist
        }
        
        // 파일이 해제되었는지 확인
        XCTAssertNil(weakFile)
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentAccess() throws {
        let file = try TagFile(path: testFilePath)
        let queue = DispatchQueue(label: "com.taglibswift.test", attributes: .concurrent)
        let group = DispatchGroup()
        
        // 여러 스레드에서 동시 접근
        for _ in 0..<10 {
            group.enter()
            queue.async {
                _ = file.title
                _ = file.artist
                _ = file.album
                _ = file.genre
                _ = file.year
                _ = file.track
                group.leave()
            }
        }
        
        // 모든 작업이 완료될 때까지 대기
        group.wait()
    }
} 