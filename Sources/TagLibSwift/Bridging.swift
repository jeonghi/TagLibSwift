import CTagLibCore
import CxxStdlib

// Bridging helpers between TagLib C++ value types and Swift standard types.
//
// The high-level `TagLibInterop` C++ helpers already return `std::string`
// (UTF-8), which CxxStdlib bridges to `Swift.String` directly, so day-to-day the
// SDK never has to touch `TagLib::String`. This extension is provided for the
// raw escape-hatch path, where a caller reaches a format-specific class that
// hands back a `TagLib::String` value.
extension String {
    /// Create a Swift `String` from a `TagLib::String`, decoding as UTF-8.
    public init(taglib taglibString: TagLib.String) {
        self = String(taglibString.to8Bit(true))
    }
}
