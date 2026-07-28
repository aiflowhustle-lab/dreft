import SwiftUI

/// Shared border + body rendering for canvas cards (compact and interactive modes).
struct CanvasCardSurface: View {
    @State private var themeState = AppThemeState.shared
    @State private var previewScrollOffset: CGFloat = 0
    @State private var previewContentHeight: CGFloat = 0

    let card: CanvasCard
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let zoom: CGFloat
    var vaultURL: URL?
    var vaultFiles: [VaultFile] = []
    var isSelected: Bool = false
    var isLinkTarget: Bool = false
    var isConnectingLine: Bool = false
    var isEditing: Bool = false
    var imageCacheRevision: Int = 0
    var onImageLoaded: () -> Void = {}
    var onUpdateContent: ((String) -> Void)? = nil
    var onTaskCheckboxTap: (() -> Void)? = nil

    private var isImage: Bool { card.kind == .image }

    private var cardColor: Color? {
        guard let hex = card.colorHex else { return nil }
        return Color(hexString: hex)
    }

    private var showsSelectionBorder: Bool { isSelected }

    private var strokeColor: Color {
        if showsSelectionBorder { return cardColor ?? AppColors.selectionStroke }
        if isConnectingLine && isLinkTarget { return AppColors.selectionStroke.opacity(0.55) }
        if let cardColor { return cardColor.opacity(0.8) }
        return isImage ? AppColors.imageCardBorder : AppColors.noteCardBorder
    }

    private var strokeWidth: CGFloat {
        if showsSelectionBorder { return 3 }
        return cardColor == nil ? 1 : 2
    }

    private var cardCornerRadius: CGFloat { isImage ? 4 : 8 }

    private var imageContentInset: CGFloat { isImage ? 4 : 0 }

    private var fillColor: Color {
        isImage ? AppColors.cardBackground : AppColors.noteCardBackground
    }

    private var noteLOD: CanvasCardLOD {
        CanvasCardLOD.resolve(
            zoom: zoom,
            isSelected: isSelected,
            isLinkTarget: isLinkTarget,
            isEditing: isEditing
        )
    }

    private var previewScrollMetrics: CanvasNoteScrollMetrics {
        CanvasNoteScrollMetrics(
            offset: CGPoint(x: 0, y: previewScrollOffset),
            contentHeight: previewContentHeight,
            viewportHeight: max(1, frameHeight - 16)
        )
    }

    var body: some View {
        Group {
            if isImage {
                imageStyledBody
            } else {
                noteStyledBody
            }
        }
    }

    private var imageStyledBody: some View {
        let inset = imageContentInset
        let innerW = max(1, frameWidth - inset * 2)
        let innerH = max(1, frameHeight - inset * 2)
        return ZStack {
            Color.clear
            cardBody
                .frame(width: innerW, height: innerH)
                .clipShape(RoundedRectangle(cornerRadius: max(2, cardCornerRadius - 1)))
        }
        .frame(width: frameWidth, height: frameHeight)
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .stroke(strokeColor, lineWidth: strokeWidth)
        )
    }

    private var noteStyledBody: some View {
        cardBody
            .frame(width: frameWidth, height: frameHeight)
            .background(
                ZStack {
                    fillColor
                    if let cardColor { cardColor.opacity(0.08) }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
    }

    @ViewBuilder
    private var cardBody: some View {
        switch card.kind {
        case .image:
            CanvasLazyCardImage(
                cardID: card.id,
                content: card.content,
                vaultURL: vaultURL,
                allowLoad: true,
                cacheRevision: imageCacheRevision,
                onLoaded: onImageLoaded
            )
        case .note, .text:
            if noteLOD == .block {
                blockCardFill
            } else {
                noteRichPreviewBody
            }
        }
    }

    private var blockCardFill: some View {
        ZStack {
            fillColor
            if let cardColor { cardColor.opacity(0.12) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var noteRichPreviewBody: some View {
        noteRichPreviewContent
    }

    @ViewBuilder
    private var noteRichPreviewContent: some View {
        let displayMarkdown = CanvasCardContent.markdownBody(
            for: card,
            vaultURL: vaultURL,
            vaultFiles: vaultFiles
        )
        let hasTasks = NoteCardTaskSupport.parsedLines(from: displayMarkdown).contains { line in
            if case .task = line { return true }
            return false
        }
        let showsTaskCheckboxOverlay = !isEditing && !isSelected && onUpdateContent != nil && hasTasks

        Group {
            if displayMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !isEditing {
                    Text(" ")
                        .font(.system(size: CanvasConstants.noteCardFontSize))
                        .foregroundStyle(themeState.theme.textPrimary)
                }
            } else if !isEditing {
                notePreviewBody(displayMarkdown: displayMarkdown)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .padding(.top, 8)
        .allowsHitTesting(isSelected && !isEditing)
        .overlay(alignment: .topLeading) {
            if showsTaskCheckboxOverlay {
                CanvasNoteCardTaskTapOverlay(
                    content: displayMarkdown,
                    maxWidth: max(1, frameWidth - 16),
                    fontSize: CanvasConstants.noteCardFontSize,
                    onToggleTaskRawLine: { rawLine in
                        onTaskCheckboxTap?()
                        toggleTask(matchingRawLine: rawLine, in: displayMarkdown)
                    }
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func notePreviewBody(displayMarkdown: String) -> some View {
        let body = CanvasNoteCardBodyView(
            content: displayMarkdown,
            vaultURL: vaultURL,
            maxImageWidth: max(1, frameWidth - 16),
            cacheRevision: imageCacheRevision,
            onContentSizeChange: onImageLoaded,
            onToggleTaskRawLine: onUpdateContent == nil ? nil : { rawLine in
                toggleTask(matchingRawLine: rawLine, in: displayMarkdown)
            }
        )
        let scrollHeight = max(1, frameHeight - 16)

        if isSelected {
            CanvasNoteCardPreviewScrollContainer(
                offsetY: $previewScrollOffset,
                contentHeight: $previewContentHeight,
                viewportHeight: scrollHeight
            ) {
                body
            }
            .overlay(alignment: .topTrailing) {
                CanvasNoteCardScrollIndicator(metrics: previewScrollMetrics)
            }
            .onChange(of: isSelected) { _, selected in
                if !selected {
                    previewScrollOffset = 0
                }
            }
        } else {
            body
                .frame(height: scrollHeight, alignment: .topLeading)
                .clipped()
        }
    }

    private func toggleTask(matchingRawLine rawLine: String, in markdown: String) {
        guard let updated = NoteCardTaskSupport.toggleTask(matchingRawLine: rawLine, in: markdown) else { return }
        onUpdateContent?(updated)
    }
}

/// Obsidian-style lightweight card — border + content + drag/tap only (no handles or connect UI).
struct CanvasCardCompactView: View {
    let card: CanvasCard
    let displayFrame: CGRect
    let zoom: CGFloat
    var vaultURL: URL?
    var vaultFiles: [VaultFile] = []
    var isLinkTarget: Bool = false
    var isConnectingLine: Bool = false
    var imageCacheRevision: Int = 0
    var onImageLoaded: () -> Void = {}
    var onUpdateContent: ((String) -> Void)? = nil
    var onSelect: () -> Void
    var onDragBegan: () -> Void
    var onMove: (CGPoint) -> Void
    var onMoveEnd: () -> Void

    @State private var dragOrigin: CGPoint?
    @State private var isDragging = false
    @State private var isPressingCard = false
    @State private var suppressNextSelect = false

    private var frameWidth: CGFloat { displayFrame.width }
    private var frameHeight: CGFloat { displayFrame.height }
    private var displayOrigin: CGPoint { displayFrame.origin }

    var body: some View {
        let surface = CanvasCardSurface(
            card: card,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            zoom: zoom,
            vaultURL: vaultURL,
            vaultFiles: vaultFiles,
            isLinkTarget: isLinkTarget,
            isConnectingLine: isConnectingLine,
            imageCacheRevision: imageCacheRevision,
            onImageLoaded: onImageLoaded,
            onUpdateContent: onUpdateContent,
            onTaskCheckboxTap: { suppressNextSelect = true }
        )
        .contentShape(Rectangle())
        .frame(width: frameWidth, height: frameHeight)
        .zIndex(isLinkTarget ? 8 : 1)
        .transaction { transaction in
            if isDragging {
                transaction.disablesAnimations = true
            }
        }

        Group {
            if card.kind == .image {
                surface.highPriorityGesture(cardDragGesture)
            } else {
                surface.gesture(cardDragGesture)
            }
        }
        .onDisappear {
            cancelActiveDrag()
        }
        #if os(macOS)
        .modifier(CanvasCardCompactCursorModifier(isGrabbing: isPressingCard))
        #endif
    }

    /// DragGesture(minimumDistance: 0) may not receive onEnded when another control steals the touch — reset parent drag state.
    private func cancelActiveDrag() {
        guard dragOrigin != nil || isDragging || isPressingCard else { return }
        dragOrigin = nil
        isDragging = false
        isPressingCard = false
        onMoveEnd()
    }

    private var cardDragGesture: some Gesture {
        let dragThreshold: CGFloat = 3
        return DragGesture(minimumDistance: 0, coordinateSpace: .named("canvasScreen"))
            .onChanged { value in
                isPressingCard = true
                if dragOrigin == nil {
                    dragOrigin = displayOrigin
                    onDragBegan()
                }
                let moved = hypot(value.translation.width, value.translation.height) > dragThreshold
                if moved { isDragging = true }
                guard let origin = dragOrigin else { return }
                let scale = max(zoom, 0.001)
                onMove(CGPoint(
                    x: origin.x + value.translation.width / scale,
                    y: origin.y + value.translation.height / scale
                ))
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) > dragThreshold
                if !moved {
                    if suppressNextSelect {
                        suppressNextSelect = false
                    } else {
                        onSelect()
                    }
                }
                dragOrigin = nil
                isDragging = false
                isPressingCard = false
                onMoveEnd()
            }
    }
}

#if os(macOS)
import AppKit

private final class CanvasCardCompactCursorGate {
    private var hasPushed = false

    func push(_ cursor: NSCursor) {
        guard !hasPushed else { return }
        cursor.push()
        hasPushed = true
    }

    func pop() {
        guard hasPushed else { return }
        NSCursor.pop()
        hasPushed = false
    }
}

private struct CanvasCardCompactCursorModifier: ViewModifier {
    let isGrabbing: Bool
    @State private var gate = CanvasCardCompactCursorGate()
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                    gate.push(isGrabbing ? .closedHand : .openHand)
                case .ended:
                    isHovering = false
                    gate.pop()
                }
            }
            .onChange(of: isGrabbing) { _, _ in
                guard isHovering else { return }
                gate.pop()
                gate.push(isGrabbing ? .closedHand : .openHand)
            }
    }
}
#endif
