import CTagLibCore

/// Smoke test that the TagLib C++ module imports and one symbol is usable.
enum TagLibCxxSmokeTest {
    static func canConstructFileRef() -> Bool {
        let ref = TagLib.FileRef()
        return ref.isNull()
    }
}
