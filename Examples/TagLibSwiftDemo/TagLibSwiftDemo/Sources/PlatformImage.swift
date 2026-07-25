import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

enum ImageCodec {
    /// Build a SwiftUI Image from raw bytes, or nil if undecodable.
    static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #elseif canImport(AppKit)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #else
        return nil
        #endif
    }

    /// Encode raw image bytes to PNG, returning (data, mimeType).
    static func pngData(from data: Data) -> (Data, String)? {
        #if canImport(UIKit)
        guard let ui = UIImage(data: data), let png = ui.pngData() else { return nil }
        return (png, "image/png")
        #elseif canImport(AppKit)
        guard let ns = NSImage(data: data),
              let tiff = ns.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return (png, "image/png")
        #else
        return nil
        #endif
    }
}
