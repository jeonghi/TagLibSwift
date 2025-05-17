import Foundation

public class TagFile {
    private var file: OpaquePointer?
    
    public init(path: String) throws {
        file = taglib_file_new(path)
        guard file != nil else {
            throw TagLibError.fileOpenFailed
        }
    }
    
    deinit {
        if let file = file {
            taglib_file_free(file)
        }
    }
    
    public var title: String {
        get {
            guard let file = file else { return "" }
            return String(cString: taglib_file_get_title(file))
        }
        set {
            guard let file = file else { return }
            taglib_file_set_title(file, newValue)
        }
    }
    
    public var artist: String {
        get {
            guard let file = file else { return "" }
            return String(cString: taglib_file_get_artist(file))
        }
        set {
            guard let file = file else { return }
            taglib_file_set_artist(file, newValue)
        }
    }
    
    public var album: String {
        get {
            guard let file = file else { return "" }
            return String(cString: taglib_file_get_album(file))
        }
        set {
            guard let file = file else { return }
            taglib_file_set_album(file, newValue)
        }
    }
    
    public var genre: String {
        get {
            guard let file = file else { return "" }
            return String(cString: taglib_file_get_genre(file))
        }
        set {
            guard let file = file else { return }
            taglib_file_set_genre(file, newValue)
        }
    }
    
    public var year: UInt {
        get {
            guard let file = file else { return 0 }
            return UInt(taglib_file_get_year(file))
        }
        set {
            guard let file = file else { return }
            taglib_file_set_year(file, UInt32(newValue))
        }
    }
    
    public var track: UInt {
        get {
            guard let file = file else { return 0 }
            return UInt(taglib_file_get_track(file))
        }
        set {
            guard let file = file else { return }
            taglib_file_set_track(file, UInt32(newValue))
        }
    }
    
    public func save() throws {
        guard let file = file else {
            throw TagLibError.fileOpenFailed
        }
        
        if taglib_file_save(file) == 0 {
            throw TagLibError.saveFailed
        }
    }
}

public enum TagLibError: Error {
    case fileOpenFailed
    case fileNotOpen
    case saveFailed
} 