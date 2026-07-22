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

/// Image card body that reads from cache first and decodes off the main thread when allowed.
struct CanvasLazyCardImage: View {
    let cardID: String
    let content: String
    var vaultURL: URL?
    var allowLoad: Bool
    var cacheRevision: Int
    var onLoaded: () -> Void

    @State private var didScheduleLoad = false

    var body: some View {
        Group {
            if let cgImage = CanvasImageCache.shared.cachedImage(forCardID: cardID, content: content) {
                CachedCardImage(cgImage: cgImage)
            } else {
                imagePlaceholder
            }
        }
        .onAppear { scheduleLoadIfNeeded() }
        .onChange(of: cacheRevision) { _, _ in
            didScheduleLoad = false
            scheduleLoadIfNeeded()
        }
        .onChange(of: allowLoad) { _, _ in
            didScheduleLoad = false
            scheduleLoadIfNeeded()
        }
    }

    private var imagePlaceholder: some View {
        ZStack {
            Color.white.opacity(0.04)
            if allowLoad {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scheduleLoadIfNeeded() {
        guard allowLoad else { return }
        if CanvasImageCache.shared.cachedImage(forCardID: cardID, content: content) != nil {
            didScheduleLoad = false
            return
        }
        guard !didScheduleLoad else { return }
        didScheduleLoad = true
        CanvasImageCache.shared.scheduleDisplayImage(
            forCardID: cardID,
            content: content,
            vaultURL: vaultURL,
            onComplete: {
                didScheduleLoad = false
                onLoaded()
            }
        )
    }
}
