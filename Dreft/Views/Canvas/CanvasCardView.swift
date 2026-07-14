import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CanvasCardView: View {
    let card: CanvasCard
    let displayFrame: CGRect
    let isSelected: Bool
    let isLinkTarget: Bool
    let isConnectingLine: Bool
    let zoom: CGFloat
    var vaultURL: URL?

    var onSelect: () -> Void
    var onDragBegan: () -> Void
    var onMove: (CGPoint) -> Void
    var onMoveEnd: () -> Void
    var onResize: (CGRect) -> Void
    var onResizeBegan: () -> Void
    var onResizeEnd: () -> Void
    var onDelete: () -> Void
    var onZoomToCard: () -> Void
    var onBeginConnect: (CanvasSide) -> Void
    var onUpdateConnect: (CGPoint) -> Void
    var onEndConnect: (CGPoint, Bool) -> Void
    var onUpdateContent: (String) -> Void
    var onUpdateTitle: (String) -> Void = { _ in }
    var onSetColor: (String) -> Void
    var shouldAutoFocus: Bool = false
    var onDidFocus: () -> Void = {}
    var onBeginContentEdit: () -> Void = {}
    var onEndContentEdit: () -> Void = {}
    var beginTitleRenameToken: Int = 0

    let cardColors: [(name: String, hex: String)]
    @Binding var showColorRow: Bool
    @Binding var showCustomColorPicker: Bool

    @State private var dragOrigin: CGPoint?
    @State private var resizeStart: (frame: CGRect, corner: String)?
    @State private var connectMoved = false
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var isPressingCard = false
    @State private var hoveredPremiumHandleID: String?
    @State private var hoveredConnectSide: CanvasSide?
    @State private var connectingSide: CanvasSide?
    @State private var isRenamingTitle = false
    @State private var titleDraft = ""
    @FocusState private var isContentFocused: Bool
    @FocusState private var isTitleFocused: Bool

    private var isImage: Bool { card.kind == .image }
    private var frameWidth: CGFloat { displayFrame.width }
    private var frameHeight: CGFloat { displayFrame.height }
    private var displayOrigin: CGPoint { displayFrame.origin }

    /// Purple chrome only when selected and not mid-drag.
    private var showsSelectionChrome: Bool {
        isSelected && !isDragging
    }

    /// Selected notes use the interior drag surface; don't attach a second drag gesture to the frame.
    private var usesExteriorDragGesture: Bool {
        !isSelected || isImage
    }

    private var showsResizeOverlay: Bool {
        isSelected && !isDragging
    }

    /// Custom color assigned to the card, if any.
    private var cardColor: Color? {
        guard let hex = card.colorHex else { return nil }
        return Color(hexString: hex)
    }

    private var strokeColor: Color {
        if showsSelectionChrome { return cardColor ?? AppColors.selectionStroke }
        if isConnectingLine && isLinkTarget { return AppColors.selectionStroke.opacity(0.55) }
        if let cardColor { return cardColor.opacity(0.8) }
        return isImage ? AppColors.imageCardBorder : AppColors.noteCardBorder
    }

    private var strokeWidth: CGFloat {
        if showsSelectionChrome { return 3 }
        return cardColor == nil ? 1 : 2
    }

    private var cardCornerRadius: CGFloat {
        isImage ? 4 : 8
    }

    /// Transparent canvas gap between image and border — always visible on image cards.
    /// In world units so it scales proportionally with the border stroke as you zoom.
    private var imageContentInset: CGFloat {
        guard isImage else { return 0 }
        return 4
    }

    private var fillColor: Color {
        isImage ? AppColors.cardBackground : AppColors.noteCardBackground
    }

    /// Toolbar layout height in screen points (before counter-scale).
    private var toolbarLayoutHeight: CGFloat { 38 }
    private var toolbarGapAboveCard: CGFloat { 12 }

    /// Counter-scale the toolbar so it stays a comfortable screen size.
    /// Clamped: doesn't grow huge when zoomed out, doesn't shrink too small when zoomed in.
    private var toolbarWorldScale: CGFloat {
        let clampedZoom = min(max(zoom, 0.45), 1.35)
        return 1 / clampedZoom
    }

    private var floatingToolbarSlotHeight: CGFloat {
        (toolbarLayoutHeight + toolbarGapAboveCard) * toolbarWorldScale
    }

    /// Offset so the toolbar slot sits fully above the card with a small gap at any zoom.
    private var floatingToolbarOffsetY: CGFloat {
        -floatingToolbarSlotHeight
    }

    private var imageTitleOffsetY: CGFloat {
        floatingToolbarOffsetY - (18 * toolbarWorldScale)
    }

    private var inlineColorRowTopPadding: CGFloat {
        8 * toolbarWorldScale
    }

    private var noteColorRowReservedHeight: CGFloat {
        (40 * toolbarWorldScale) + inlineColorRowTopPadding
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardFrame
                .contentShape(Rectangle())
                .if(usesExteriorDragGesture) { view in
                    view
                        .highPriorityGesture(cardDragGesture)
                        .canvasCardCursor(isGrabbing: isPressingCard)
                }

            if isSelected {
                cardInteriorDragSurface
                    .zIndex(1)
                if showsResizeOverlay {
                    premiumEdgeResizeStrips
                        .zIndex(2)
                    premiumSelectionHandles
                        .zIndex(4)
                }
            }

            if isImage {
                imageTitleLabel
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .offset(y: showsSelectionChrome ? imageTitleOffsetY : (-18 * toolbarWorldScale))
                    .onChange(of: beginTitleRenameToken) { _, _ in
                        guard beginTitleRenameToken > 0 else { return }
                        beginTitleRename()
                    }
                    .if(!isResizing && !isRenamingTitle) { view in
                        view
                            .highPriorityGesture(cardDragGesture)
                            .canvasCardCursor(isGrabbing: isPressingCard)
                    }
            }

            if showColorRow && showsSelectionChrome {
                inlineColorSwatchRow
                    .zIndex(3)
            }

        }
        .frame(width: frameWidth, height: frameHeight)
        .zIndex(isSelected ? 10 : (isLinkTarget ? 8 : 1))
    }

    private var imageDisplayTitle: String {
        if let title = card.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if !VaultFilesystem.isEmbeddedImageContent(card.content) {
            let stem = URL(fileURLWithPath: card.content).deletingPathExtension().lastPathComponent
            if !stem.isEmpty { return stem }
        }
        return CanvasStore.defaultImageTitle
    }

    private var imageTitleLabel: some View {
        Group {
            if isRenamingTitle {
                TextField("Image name", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .focused($isTitleFocused)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AppColors.canvasBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(AppColors.selectionStroke, lineWidth: 1.5)
                            )
                    )
                    .frame(width: max(80, frameWidth * 0.85))
                    .onSubmit { commitTitleRename() }
                    .onAppear {
                        DispatchQueue.main.async { isTitleFocused = true }
                    }
                    .onChange(of: isTitleFocused) { _, focused in
                        if !focused { commitTitleRename() }
                    }
            } else {
                Text(imageDisplayTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: frameWidth, alignment: .center)
                    .onTapGesture(count: 2) {
                        onSelect()
                        beginTitleRename()
                    }
            }
        }
    }

    private func beginTitleRename() {
        titleDraft = imageDisplayTitle
        isRenamingTitle = true
    }

    private func commitTitleRename() {
        guard isRenamingTitle else { return }
        isRenamingTitle = false
        onUpdateTitle(titleDraft)
    }

    private var cardFrame: some View {
        styledCardBody
    }

    private var styledCardBody: some View {
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
            if let cgImage = CanvasImageCache.shared.displayImage(
                forCardID: card.id,
                content: card.content,
                vaultURL: vaultURL
            ) {
                CachedCardImage(cgImage: cgImage)
            } else {
                ZStack {
                    Color.white.opacity(0.04)
                    ProgressView().controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .note, .text:
            ZStack {
                TextEditor(text: Binding(get: { card.content }, set: onUpdateContent))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .padding(.top, showColorRow ? noteColorRowReservedHeight : 8)
                    .focused($isContentFocused)
                    .allowsHitTesting(isContentFocused)
                    .onAppear {
                        guard shouldAutoFocus else { return }
                        DispatchQueue.main.async {
                            isContentFocused = true
                            onDidFocus()
                        }
                    }
                    .onChange(of: shouldAutoFocus) { _, shouldFocus in
                        guard shouldFocus else { return }
                        DispatchQueue.main.async {
                            isContentFocused = true
                            onDidFocus()
                        }
                    }
                    .onChange(of: isContentFocused) { _, focused in
                        if focused {
                            onBeginContentEdit()
                        } else {
                            onEndContentEdit()
                        }
                    }

                if !isContentFocused {
                    Color.clear
                        .contentShape(Rectangle())
                }
            }
            .onChange(of: isSelected) { _, selected in
                if !selected {
                    isContentFocused = false
                }
            }
        }
    }

    private var cardDragGesture: some Gesture {
        let dragThreshold: CGFloat = 3
        return DragGesture(minimumDistance: 0, coordinateSpace: .named("canvasScreen"))
            .onChanged { value in
                guard !isResizing else { return }
                if isContentFocused {
                    isContentFocused = false
                }
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
                    if isSelected && !isImage && !isContentFocused {
                        beginEditingNote()
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

    private func beginEditingNote() {
        guard !isImage else { return }
        DispatchQueue.main.async {
            isContentFocused = true
        }
    }

    @ViewBuilder
    private var inlineColorSwatchRow: some View {
        CanvasCardColorSwatchRow(
            activeColorHex: card.colorHex,
            frameWidth: frameWidth,
            zoom: zoom,
            cardColors: cardColors,
            showCustomColorPicker: $showCustomColorPicker,
            onSetColor: onSetColor
        )
        .scaleEffect(toolbarWorldScale, anchor: .top)
        .frame(width: frameWidth, alignment: .center)
        .padding(.top, isImage ? (imageContentInset + inlineColorRowTopPadding) : inlineColorRowTopPadding)
        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
    }

    private var handleScreenScale: CGFloat {
        1 / max(zoom, 0.12)
    }

    /// Converts screen pixels to world/card units at the current zoom.
    private func screenPixels(_ px: CGFloat) -> CGFloat {
        px * handleScreenScale
    }

    private var connectHitSize: CGFloat {
        screenPixels(30)
    }

    private var handleHitSize: CGFloat {
        screenPixels(26)
    }

    private var cornerHandleVisual: CGFloat { 8 }
    private var edgeHandleVisual: CGFloat { 9 }

    private struct PremiumHandle: Identifiable {
        enum Kind { case corner, edge(CanvasSide) }
        let id: String
        let kind: Kind
        let resizeKey: String
        let center: CGPoint
    }

    private var premiumHandles: [PremiumHandle] {
        [
            PremiumHandle(id: "nw", kind: .corner, resizeKey: "nw", center: CGPoint(x: 0, y: 0)),
            PremiumHandle(id: "ne", kind: .corner, resizeKey: "ne", center: CGPoint(x: frameWidth, y: 0)),
            PremiumHandle(id: "se", kind: .corner, resizeKey: "se", center: CGPoint(x: frameWidth, y: frameHeight)),
            PremiumHandle(id: "sw", kind: .corner, resizeKey: "sw", center: CGPoint(x: 0, y: frameHeight)),
            PremiumHandle(id: "n", kind: .edge(.top), resizeKey: "n", center: CGPoint(x: frameWidth / 2, y: 0)),
            PremiumHandle(id: "s", kind: .edge(.bottom), resizeKey: "s", center: CGPoint(x: frameWidth / 2, y: frameHeight)),
            PremiumHandle(id: "w", kind: .edge(.left), resizeKey: "w", center: CGPoint(x: 0, y: frameHeight / 2)),
            PremiumHandle(id: "e", kind: .edge(.right), resizeKey: "e", center: CGPoint(x: frameWidth, y: frameHeight / 2)),
        ]
    }

    /// Full-edge resize strips — center gap keeps the 4 connection dots free.
    private var premiumEdgeResizeStrips: some View {
        let t = screenPixels(10)
        let gapX = min(connectHitSize, frameWidth * 0.34)
        let gapY = min(connectHitSize, frameHeight * 0.34)
        let segW = max(0, (frameWidth - gapX) / 2)
        let segH = max(0, (frameHeight - gapY) / 2)

        return ZStack {
            if segW > 4 {
                premiumEdgeStrip(size: CGSize(width: segW, height: t), center: CGPoint(x: segW / 2, y: t / 2), handle: "n")
                premiumEdgeStrip(size: CGSize(width: segW, height: t), center: CGPoint(x: frameWidth - segW / 2, y: t / 2), handle: "n")
                premiumEdgeStrip(size: CGSize(width: segW, height: t), center: CGPoint(x: segW / 2, y: frameHeight - t / 2), handle: "s")
                premiumEdgeStrip(size: CGSize(width: segW, height: t), center: CGPoint(x: frameWidth - segW / 2, y: frameHeight - t / 2), handle: "s")
            }
            if segH > 4 {
                premiumEdgeStrip(size: CGSize(width: t, height: segH), center: CGPoint(x: t / 2, y: segH / 2), handle: "w")
                premiumEdgeStrip(size: CGSize(width: t, height: segH), center: CGPoint(x: t / 2, y: frameHeight - segH / 2), handle: "w")
                premiumEdgeStrip(size: CGSize(width: t, height: segH), center: CGPoint(x: frameWidth - t / 2, y: segH / 2), handle: "e")
                premiumEdgeStrip(size: CGSize(width: t, height: segH), center: CGPoint(x: frameWidth - t / 2, y: frameHeight - segH / 2), handle: "e")
            }
        }
    }

    private func premiumEdgeStrip(size: CGSize, center: CGPoint, handle: String) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .position(center)
            .simultaneousGesture(resizeDragGesture(handle: handle))
    }

    private var premiumSelectionHandles: some View {
        ZStack {
            ForEach(premiumHandles) { handle in
                premiumHandleView(handle)
                    .position(handle.center)
            }
        }
    }

    @ViewBuilder
    private func premiumHandleView(_ handle: PremiumHandle) -> some View {
        let isHovered = hoveredPremiumHandleID == handle.id
        let isConnectHovered = {
            if case .edge(let side) = handle.kind { return hoveredConnectSide == side }
            return false
        }()
        let isConnectActive = {
            if case .edge(let side) = handle.kind { return connectingSide == side }
            return false
        }()
        let isActive = isResizing && resizeStart?.corner == handle.resizeKey
        let scale = 1 / max(zoom, 0.45)
        let hit = handleHitSize

        let body = ZStack {
            Color.clear
                .frame(width: hit, height: hit)
                .contentShape(Rectangle())

            Group {
                switch handle.kind {
                case .corner:
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(AppColors.resizeCornerHandle)
                        .frame(width: cornerHandleVisual, height: cornerHandleVisual)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .stroke(Color.white.opacity(0.4), lineWidth: 0.75)
                        )
                case .edge:
                    Circle()
                        .fill(AppColors.resizeEdgeHandle)
                        .frame(width: edgeHandleVisual, height: edgeHandleVisual)
                        .overlay(Circle().stroke(Color.white.opacity(0.42), lineWidth: 0.75))
                        .shadow(
                            color: AppColors.selectionStroke.opacity(isConnectHovered || isConnectActive ? 0.55 : 0.2),
                            radius: isConnectHovered || isConnectActive ? 5 : 1
                        )
                        .scaleEffect(isConnectActive ? 1.2 : 1)
                }
            }
            .scaleEffect(scale * (isHovered || isActive || isConnectActive ? 1.14 : 1))
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isConnectActive)
        }
        .onHover { hovering in
            if hovering {
                hoveredPremiumHandleID = handle.id
            } else if hoveredPremiumHandleID == handle.id {
                hoveredPremiumHandleID = nil
            }
            if case .edge(let side) = handle.kind {
                if hovering {
                    hoveredConnectSide = side
                } else if hoveredConnectSide == side {
                    hoveredConnectSide = nil
                }
            }
        }

        switch handle.kind {
        case .corner:
            body.highPriorityGesture(resizeDragGesture(handle: handle.resizeKey))
        case .edge(let side):
            body.highPriorityGesture(connectDragGesture(side: side))
        }
    }

    private func connectDragGesture(side: CanvasSide) -> some Gesture {
        let dragThreshold: CGFloat = 4
        return DragGesture(minimumDistance: 0, coordinateSpace: .named("canvasScreen"))
            .onChanged { value in
                guard !isResizing else { return }
                let movedEnough = hypot(value.translation.width, value.translation.height) > dragThreshold
                if movedEnough && !connectMoved {
                    connectMoved = true
                    connectingSide = side
                    hoveredConnectSide = side
                    onBeginConnect(side)
                }
                if connectMoved {
                    onUpdateConnect(value.location)
                }
            }
            .onEnded { value in
                defer {
                    connectMoved = false
                    connectingSide = nil
                }
                guard connectMoved else { return }
                let moved = hypot(value.translation.width, value.translation.height) > dragThreshold
                onEndConnect(value.location, moved)
            }
    }

    /// Hand + drag for card interior. Image cards use the full frame; notes use the full frame too
    /// so dragging stays reliable while resize/connect handles sit above this layer.
    private var cardInteriorDragSurface: some View {
        Color.clear
            .frame(width: frameWidth, height: frameHeight)
            .contentShape(Rectangle())
            .allowsHitTesting(!isResizing && !isContentFocused)
            .highPriorityGesture(cardDragGesture)
            .canvasCardCursor(isGrabbing: isPressingCard)
    }

    private func resizeDragGesture(handle: String) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("canvasScreen"))
            .onChanged { value in
                guard !connectMoved, !isConnectingLine else { return }
                if resizeStart == nil {
                    isResizing = true
                    isPressingCard = false
                    resizeStart = (displayFrame, handle)
                    onResizeBegan()
                }
                guard let start = resizeStart else { return }
                let scale = max(zoom, 0.001)
                applyResize(start: start.frame, handle: start.corner, translation: CGSize(
                    width: value.translation.width / scale,
                    height: value.translation.height / scale
                ))
            }
            .onEnded { _ in
                resizeStart = nil
                isResizing = false
                onResizeEnd()
            }
    }

    private func applyResize(start: CGRect, handle: String, translation: CGSize) {
        var frame = start
        let dx = translation.width
        let dy = translation.height
        let minW: CGFloat = 40
        let minH: CGFloat = 40

        switch handle {
        case "n":
            frame.origin.y = start.origin.y + dy
            frame.size.height = max(minH, start.height - dy)
        case "s":
            frame.size.height = max(minH, start.height + dy)
        case "w":
            frame.origin.x = start.origin.x + dx
            frame.size.width = max(minW, start.width - dx)
        case "e":
            frame.size.width = max(minW, start.width + dx)
        case "ne":
            frame.size.width = max(minW, start.width + dx)
            frame.size.height = max(minH, start.height - dy)
            frame.origin.y = start.maxY - frame.height
        case "se":
            frame.size.width = max(minW, start.width + dx)
            frame.size.height = max(minH, start.height + dy)
        case "sw":
            frame.size.width = max(minW, start.width - dx)
            frame.size.height = max(minH, start.height + dy)
            frame.origin.x = start.maxX - frame.width
        case "nw":
            frame.size.width = max(minW, start.width - dx)
            frame.size.height = max(minH, start.height - dy)
            frame.origin.x = start.maxX - frame.width
            frame.origin.y = start.maxY - frame.height
        default: break
        }
        onResize(frame)
    }

    private func handlePosition(for side: CanvasSide) -> CGPoint {
        switch side {
        case .top: CGPoint(x: frameWidth / 2, y: 0)
        case .bottom: CGPoint(x: frameWidth / 2, y: frameHeight)
        case .left: CGPoint(x: 0, y: frameHeight / 2)
        case .right: CGPoint(x: frameWidth, y: frameHeight / 2)
        }
    }
}

extension Color {
    /// "#RRGGBB" representation used for canvas card colors.
    var canvasHexString: String {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
        #elseif canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
        #else
        return "#FFFFFF"
        #endif
    }

    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

// MARK: - Resize cursors (macOS)

#if os(macOS)
private struct CanvasCardCursorModifier: ViewModifier {
    let isGrabbing: Bool
    @State private var isHovering = false
    @State private var hasPushed = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                    pushCursor()
                case .ended:
                    isHovering = false
                    popCursor()
                }
            }
            .onChange(of: isGrabbing) { _, _ in
                guard isHovering else { return }
                popCursor()
                pushCursor()
            }
    }

    private func pushCursor() {
        guard !hasPushed else { return }
        (isGrabbing ? NSCursor.closedHand : NSCursor.openHand).push()
        hasPushed = true
    }

    private func popCursor() {
        guard hasPushed else { return }
        NSCursor.pop()
        hasPushed = false
    }
}
#endif

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func canvasCardCursor(isGrabbing: Bool) -> some View {
        #if os(macOS)
        modifier(CanvasCardCursorModifier(isGrabbing: isGrabbing))
        #else
        self
        #endif
    }
}
#if os(macOS)
import AppKit
#endif
