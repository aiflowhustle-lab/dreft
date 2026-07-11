import CoreGraphics
import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum ImagePixelSize {
    static func from(data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    #if canImport(UIKit)
    static func from(image: UIImage) -> CGSize {
        if let cg = image.cgImage {
            return CGSize(width: cg.width, height: cg.height)
        }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }
    #endif

    #if canImport(AppKit)
    static func from(image: NSImage) -> CGSize {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }
    #endif
}
