import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct CachedCardImage: View {
    let cgImage: CGImage

    var body: some View {
        #if canImport(UIKit)
        Image(decorative: cgImage, scale: 1, orientation: .up)
            .resizable()
            .interpolation(.medium)
            .scaledToFill()
            .clipped()
        #elseif canImport(AppKit)
        Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
            .resizable()
            .interpolation(.medium)
            .scaledToFill()
            .clipped()
        #endif
    }
}
