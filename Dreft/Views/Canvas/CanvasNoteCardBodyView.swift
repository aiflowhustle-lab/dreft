import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Renders note card markdown with inline images for `![[asset.jpg]]` embeds.
struct CanvasNoteCardBodyView: View {
    enum ContentMode {
        case full
        case imagesOnly
    }

    @State private var themeState = AppThemeState.shared

    let content: String
    var vaultURL: URL?
    var maxImageWidth: CGFloat
    var fontSize: CGFloat = CanvasConstants.noteCardFontSize
    var contentMode: ContentMode = .full
    var cacheRevision: Int = 0
    var onContentSizeChange: () -> Void = {}
    var onToggleTaskRawLine: ((String) -> Void)? = nil

    @State private var imageCacheRevision = 0

    private var segments: [NoteCardContentSegment] {
        NoteCardEmbedSupport.segments(from: content, vaultURL: vaultURL)
    }

    private var flowRows: [NoteCardFlowRow] {
        NoteCardContentLayout.flowRows(
            from: segments,
            maxWidth: maxImageWidth,
            fontSize: fontSize,
            imageWidthForPath: estimatedImageWidth(for:)
        )
    }

    var body: some View {
        let themeRevision = themeState.revision
        VStack(alignment: .leading, spacing: NoteCardContentLayout.rowSpacing) {
            if flowRows.isEmpty {
                if contentMode == .full {
                    Text(" ")
                        .font(.system(size: fontSize))
                        .foregroundStyle(themeState.theme.textPrimary)
                }
            } else {
                ForEach(flowRows) { row in
                    flowRowView(row)
                }
            }
        }
        .id(themeRevision)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: cacheRevision) { _, _ in
            deferImageLayoutRefresh()
        }
    }

    @ViewBuilder
    private func flowRowView(_ row: NoteCardFlowRow) -> some View {
        switch row {
        case .text(let text):
            if contentMode == .full {
                noteText(text)
            }
        case .inline(let text, let path):
            HStack(alignment: .top, spacing: NoteCardContentLayout.inlineSpacing) {
                if contentMode == .full {
                    Text(NotePreviewCache.canvasCardPreview(for: text))
                        .font(.system(size: fontSize))
                        .foregroundStyle(themeState.theme.textPrimary)
                        .tint(AppColors.noteLink)
                        .fixedSize(horizontal: true, vertical: false)
                }
                inlineImageView(path: path)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .image(let path):
            inlineImageView(path: path)
        case .verticalWhitespace(let height):
            if contentMode == .full {
                Spacer().frame(height: height)
            }
        }
    }

    @ViewBuilder
    private func inlineImageView(path: String) -> some View {
        if contentMode == .full || contentMode == .imagesOnly {
            NoteCardInlineImage(
                vaultPath: path,
                vaultURL: vaultURL,
                maxWidth: maxImageWidth,
                cacheRevision: imageCacheRevision + cacheRevision,
                onLoaded: {
                    deferImageLayoutRefresh()
                }
            )
        }
    }

    @ViewBuilder
    private func noteText(_ text: String) -> some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else {
            let lines = NoteCardTaskSupport.parsedLines(from: text)
            if lines.contains(where: { if case .task = $0 { return true }; return false }) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { _, line in
                        noteTextLine(line)
                    }
                }
                .frame(maxWidth: maxImageWidth, alignment: .leading)
            } else {
                Text(NotePreviewCache.canvasCardPreview(for: text))
                    .font(.system(size: fontSize))
                    .foregroundStyle(themeState.theme.textPrimary)
                    .tint(AppColors.noteLink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: maxImageWidth, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func noteTextLine(_ line: NoteCardTextLine) -> some View {
        switch line {
        case .plain(let value):
            if value.isEmpty {
                Spacer().frame(height: fontSize * 0.35)
            } else {
                Text(NotePreviewCache.canvasCardPreview(for: value))
                    .font(.system(size: fontSize))
                    .foregroundStyle(themeState.theme.textPrimary)
                    .tint(AppColors.noteLink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: maxImageWidth, alignment: .leading)
            }
        case .task(let checked, let value, let rawLine):
            HStack(alignment: .top, spacing: NoteCardTaskSupport.checkboxSpacing) {
                Group {
                    if onToggleTaskRawLine != nil {
                        Button {
                            onToggleTaskRawLine?(rawLine)
                        } label: {
                            NoteCardTaskCheckbox(checked: checked)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NoteCardTaskCheckbox(checked: checked)
                    }
                }
                .padding(.top, max(2, fontSize * 0.12))

                Text(NotePreviewCache.canvasCardPreview(for: value))
                    .font(.system(size: fontSize))
                    .foregroundStyle(checked ? AppColors.textSecondary : themeState.theme.textPrimary)
                    .strikethrough(checked, color: AppColors.textSecondary)
                    .tint(AppColors.noteLink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        maxWidth: max(1, maxImageWidth - NoteCardTaskSupport.lineLeadingInset(fontSize: fontSize)),
                        alignment: .leading
                    )
            }
            .frame(maxWidth: maxImageWidth, alignment: .leading)
        }
    }

    private func estimatedImageWidth(for path: String) -> CGFloat {
        NoteCardInlineImageMetrics.estimatedSize(
            for: path,
            vaultURL: vaultURL,
            maxWidth: maxImageWidth
        ).width
    }

    private func deferImageLayoutRefresh() {
        Task { @MainActor in
            imageCacheRevision += 1
            onContentSizeChange()
        }
    }
}

struct CanvasNoteCardEmbeddedImagesView: View {
    let content: String
    var vaultURL: URL?
    var maxImageWidth: CGFloat
    var cacheRevision: Int = 0

    var body: some View {
        CanvasNoteCardBodyView(
            content: content,
            vaultURL: vaultURL,
            maxImageWidth: maxImageWidth,
            contentMode: .imagesOnly,
            cacheRevision: cacheRevision
        )
    }
}

/// Positions note-card embed images over a text editor using the same flow rules as preview.
struct CanvasNoteCardImageOverlay: View {
    let content: String
    var vaultURL: URL?
    var maxImageWidth: CGFloat
    var fontSize: CGFloat
    var cacheRevision: Int = 0
    var scrollOffset: CGPoint = .zero
    var onImageLayoutChange: (() -> Void)? = nil

    @State private var imageCacheRevision = 0

    private var segments: [NoteCardContentSegment] {
        NoteCardEmbedSupport.segments(from: content, vaultURL: vaultURL)
    }

    private var placements: [NoteCardImagePlacement] {
        NoteCardContentLayout.imagePlacements(
            from: segments,
            maxWidth: maxImageWidth,
            fontSize: fontSize,
            imageSizeForPath: { path in
                NoteCardInlineImageMetrics.estimatedSize(
                    for: path,
                    vaultURL: vaultURL,
                    maxWidth: maxImageWidth
                )
            }
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(placements) { placement in
                NoteCardInlineImage(
                    vaultPath: placement.path,
                    vaultURL: vaultURL,
                    maxWidth: maxImageWidth,
                    cacheRevision: imageCacheRevision + cacheRevision,
                    onLoaded: {
                        deferImageLayoutRefresh()
                        onImageLayoutChange?()
                    }
                )
                .offset(x: placement.origin.x, y: placement.origin.y)
            }
        }
        .offset(x: -scrollOffset.x, y: -scrollOffset.y)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .onChange(of: cacheRevision) { _, _ in
            deferImageLayoutRefresh()
        }
        .onChange(of: content) { _, _ in
            deferImageLayoutRefresh()
        }
    }

    private func deferImageLayoutRefresh() {
        Task { @MainActor in
            imageCacheRevision += 1
        }
    }
}

enum NoteCardInlineImageMetrics {
    static func blockAttachmentSize(for path: String, vaultURL: URL?, maxWidth: CGFloat) -> CGSize {
        let cacheID = "note-embed|\(path)"
        if let cgImage = CanvasImageCache.shared.cachedImage(forCardID: cacheID, content: path)
            ?? CanvasImageCache.shared.displayImage(forCardID: cacheID, content: path, vaultURL: vaultURL) {
            let natural = displaySize(for: cgImage, maxWidth: maxWidth)
            if natural.width >= maxWidth * 0.92 {
                return natural
            }
            return CGSize(width: maxWidth, height: natural.height * (maxWidth / max(natural.width, 1)))
        }
        return estimatedSize(for: path, vaultURL: vaultURL, maxWidth: maxWidth)
    }

    static func estimatedSize(for path: String, vaultURL: URL?, maxWidth: CGFloat) -> CGSize {
        let cacheID = "note-embed|\(path)"
        if let cgImage = CanvasImageCache.shared.cachedImage(forCardID: cacheID, content: path) {
            return displaySize(for: cgImage, maxWidth: maxWidth)
        }
        let width = min(maxWidth, 160)
        return CGSize(width: width, height: min(maxWidth * 0.6, 120))
    }

    static func recordDisplaySize(_ size: CGSize, path: String, maxWidth: CGFloat) {
        NoteCardEmbedLayoutMetrics.store(height: size.height, path: path, maxWidth: maxWidth)
    }

    static func displaySize(for cgImage: CGImage, maxWidth: CGFloat) -> CGSize {
        let naturalSize = pointSize(for: cgImage)
        guard naturalSize.width > 0 else {
            return CGSize(width: min(maxWidth, 160), height: min(maxWidth * 0.6, 120))
        }
        let width = min(maxWidth, naturalSize.width)
        let height = naturalSize.height * (width / naturalSize.width)
        return CGSize(width: width, height: height)
    }

    /// Point size for a cached thumbnail — matches SwiftUI `Image(decorative:scale:)`.
    private static func pointSize(for cgImage: CGImage) -> CGSize {
        #if canImport(UIKit)
        let image = UIImage(cgImage: cgImage, scale: screenScale, orientation: .up)
        return image.size
        #elseif canImport(AppKit)
        let scale = screenScale
        let size = NSSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
        return size
        #else
        return CGSize(
            width: CGFloat(cgImage.width) / screenScale,
            height: CGFloat(cgImage.height) / screenScale
        )
        #endif
    }

    private static var screenScale: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.scale
        #elseif canImport(AppKit)
        NSScreen.main?.backingScaleFactor ?? 2
        #else
        2
        #endif
    }
}

/// Measured embed image heights so text layout matches overlay frames exactly.
enum NoteCardEmbedLayoutMetrics {
    private static var measuredHeights: [String: CGFloat] = [:]

    static func cacheKey(path: String, maxWidth: CGFloat) -> String {
        "\(path)|\(Int(maxWidth.rounded()))"
    }

    static func store(height: CGFloat, path: String, maxWidth: CGFloat) {
        measuredHeights[cacheKey(path: path, maxWidth: maxWidth)] = height
    }

    static func reservedHeight(for path: String, maxWidth: CGFloat, vaultURL: URL?) -> CGFloat {
        let key = cacheKey(path: path, maxWidth: maxWidth)
        if let measured = measuredHeights[key] {
            return measured
        }
        let cacheID = "note-embed|\(path)"
        if let cgImage = CanvasImageCache.shared.cachedImage(forCardID: cacheID, content: path) {
            return NoteCardInlineImageMetrics.displaySize(for: cgImage, maxWidth: maxWidth).height
        }
        return min(maxWidth * 0.6, 120)
    }
}

struct NoteCardInlineImage: View {
    let vaultPath: String
    var vaultURL: URL?
    var maxWidth: CGFloat
    var cacheRevision: Int
    var onLoaded: () -> Void

    @State private var didScheduleLoad = false

    private var cacheID: String {
        "note-embed|\(vaultPath)"
    }

    var body: some View {
        Group {
            if let cgImage = CanvasImageCache.shared.cachedImage(forCardID: cacheID, content: vaultPath) {
                inlineImage(cgImage)
            } else {
                loadingPlaceholder
            }
        }
        .onAppear { scheduleLoadIfNeeded() }
        .onChange(of: cacheRevision) { _, _ in
            didScheduleLoad = false
            scheduleLoadIfNeeded()
        }
    }

    private func inlineImage(_ cgImage: CGImage) -> some View {
        let size = NoteCardInlineImageMetrics.displaySize(for: cgImage, maxWidth: maxWidth)
        NoteCardInlineImageMetrics.recordDisplaySize(size, path: vaultPath, maxWidth: maxWidth)
        #if canImport(UIKit)
        return Image(decorative: cgImage, scale: UIScreen.main.scale, orientation: .up)
            .resizable()
            .interpolation(.medium)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        #elseif canImport(AppKit)
        return Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: size.width, height: size.height)))
            .resizable()
            .interpolation(.medium)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        #endif
    }

    private var loadingPlaceholder: some View {
        let size = NoteCardInlineImageMetrics.estimatedSize(
            for: vaultPath,
            vaultURL: vaultURL,
            maxWidth: maxWidth
        )
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppColors.borderSubtle.opacity(0.35))
            .frame(width: size.width, height: size.height, alignment: .leading)
            .overlay {
                ProgressView()
                    .controlSize(.small)
            }
    }

    private func scheduleLoadIfNeeded() {
        guard let vaultURL else { return }
        if CanvasImageCache.shared.cachedImage(forCardID: cacheID, content: vaultPath) != nil {
            didScheduleLoad = false
            Task { @MainActor in onLoaded() }
            return
        }
        guard !didScheduleLoad else { return }
        didScheduleLoad = true
        CanvasImageCache.shared.scheduleDisplayImage(
            forCardID: cacheID,
            content: vaultPath,
            vaultURL: vaultURL,
            onComplete: {
                didScheduleLoad = false
                Task { @MainActor in onLoaded() }
            }
        )
    }
}
