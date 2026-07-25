import Foundation

/// A single value inside a complex property's `VariantMap`, mirroring the subset
/// of `TagLib::Variant` types that map cleanly onto Swift.
///
/// TagLib's `Variant` can also hold `Double`, `ByteVectorList`, `Map` and
/// nested `List<Variant>`; those exotic types decode to ``unsupported`` rather
/// than being silently dropped or misrepresented. A plain value type — no
/// imported C++ reference types — so the iOS 13 / macOS 10.15 floor is preserved.
public enum ComplexValue: Equatable {
    /// A UTF-8 string (`Variant::String`).
    case string(String)
    /// An integer (`Variant::Int` / `UInt` / `LongLong` / `ULongLong`).
    case int(Int)
    /// A boolean (`Variant::Bool`).
    case bool(Bool)
    /// Raw bytes (`Variant::ByteVector`), e.g. embedded image data.
    case data(Data)
    /// An ordered list of strings (`Variant::StringList`).
    case stringList([String])
    /// A `Variant` type `ComplexValue` does not model (Double, nested lists/maps).
    case unsupported
}
