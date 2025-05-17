import Foundation
import TagLibCBridge

public class TagFile {
    private var file: OpaquePointer?
    
    public init(path: String) throws {
        taglib_clear_error()
        file = taglib_file_new(path)
        guard file != nil else {
            throw TagLibError.fileOpenFailed(String(cString: taglib_get_last_error()))
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
            taglib_clear_error()
            return String(cString: taglib_file_get_title(file))
        }
        set {
            guard let file = file else { return }
            taglib_clear_error()
            taglib_file_set_title(file, newValue)
        }
    }
    
    public var artist: String {
        get {
            guard let file = file else { return "" }
            taglib_clear_error()
            return String(cString: taglib_file_get_artist(file))
        }
        set {
            guard let file = file else { return }
            taglib_clear_error()
            taglib_file_set_artist(file, newValue)
        }
    }
    
    public var album: String {
        get {
            guard let file = file else { return "" }
            taglib_clear_error()
            return String(cString: taglib_file_get_album(file))
        }
        set {
            guard let file = file else { return }
            taglib_clear_error()
            taglib_file_set_album(file, newValue)
        }
    }
    
    public var genre: String {
        get {
            guard let file = file else { return "" }
            taglib_clear_error()
            return String(cString: taglib_file_get_genre(file))
        }
        set {
            guard let file = file else { return }
            taglib_clear_error()
            taglib_file_set_genre(file, newValue)
        }
    }
    
    public var year: UInt {
        get {
            guard let file = file else { return 0 }
            taglib_clear_error()
            return UInt(taglib_file_get_year(file))
        }
        set {
            guard let file = file else { return }
            taglib_clear_error()
            taglib_file_set_year(file, UInt32(newValue))
        }
    }
    
    public var track: UInt {
        get {
            guard let file = file else { return 0 }
            taglib_clear_error()
            return UInt(taglib_file_get_track(file))
        }
        set {
            guard let file = file else { return }
            taglib_clear_error()
            taglib_file_set_track(file, UInt32(newValue))
        }
    }
    
    public func save() throws {
        guard let file = file else {
            throw TagLibError.fileOpenFailed("File not open")
        }
        
        taglib_clear_error()
        if taglib_file_save(file) == 0 {
            throw TagLibError.saveFailed(String(cString: taglib_get_last_error()))
        }
    }
    
    public var isValid: Bool {
        guard let file = file else { return false }
        return taglib_file_is_valid(file) != 0
    }
}

public enum TagLibError: Error {
    case fileOpenFailed(String)
    case fileNotOpen
    case saveFailed(String)
    
    public var localizedDescription: String {
        switch self {
        case .fileOpenFailed(let message):
            return "Failed to open file: \(message)"
        case .fileNotOpen:
            return "File is not open"
        case .saveFailed(let message):
            return "Failed to save file: \(message)"
        }
    }
} 