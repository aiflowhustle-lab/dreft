import SwiftUI

/// Floating card toolbar rendered in screen space above connection lines.
struct CanvasCardFloatingToolbarLayer: View {
    let card: CanvasCard
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let zoom: CGFloat
    let cardColors: [(name: String, hex: String)]
    @Binding var showColorRow: Bool
    @Binding var showCustomColorPicker: Bool

    var onDelete: () -> Void
    var onZoomToCard: () -> Void
    var onSetColor: (String) -> Void
    var onBeginEditingNote: () -> Void
    var onRenameImage: () -> Void = {}

    private var isImage: Bool { card.kind == .image }

    private var toolbarLayoutHeight: CGFloat { 38 }
    private var toolbarGapAboveCard: CGFloat { 12 }
    private var colorRowLayoutHeight: CGFloat { 40 }
    /// Visible gap between the icon toolbar and the color palette row.
    private var colorRowGap: CGFloat { 5 }

    private var toolbarWorldScale: CGFloat {
        let clampedZoom = min(max(zoom, 0.45), 1.35)
        return 1 / clampedZoom
    }

    /// World-space spacer so the visible gap stays `colorRowGap` screen points at any zoom.
    private var colorRowGapWorld: CGFloat {
        colorRowGap / max(toolbarWorldScale * zoom, 0.001)
    }

    /// Toolbar top edge — constant so opening the color row doesn't shift the icon bar.
    private var pinnedToolbarTopY: CGFloat {
        -(toolbarGapAboveCard + toolbarLayoutHeight) * toolbarWorldScale
    }

    /// Hit-test band above the card — grows upward when the color row is open.
    private var floatingToolbarSlotHeight: CGFloat {
        let base = (toolbarGapAboveCard + toolbarLayoutHeight) * toolbarWorldScale
        let colorExtra = showColorRow ? (colorRowLayoutHeight + colorRowGap) * toolbarWorldScale : 0
        return base + colorExtra
    }

    private var floatingToolbarOffsetY: CGFloat {
        -floatingToolbarSlotHeight
    }

    /// Screen-space rect for hit-testing — keeps toolbar clicks from starting edge drags / dismiss taps.
    static func screenHitRect(
        worldFrame: CGRect,
        zoom: CGFloat,
        showColorRow: Bool,
        worldToScreen: (CGPoint) -> CGPoint
    ) -> CGRect {
        let toolbarWorldScale = 1 / min(max(zoom, 0.45), 1.35)
        let colorExtra: CGFloat = showColorRow ? 45 : 0
        let slotHeight = (CGFloat(38 + 12) + colorExtra) * toolbarWorldScale
        let screenOrigin = worldToScreen(worldFrame.origin)
        let screenWidth = worldFrame.width * zoom
        let top = screenOrigin.y + (-slotHeight) * zoom
        let height = slotHeight * zoom
        return CGRect(x: screenOrigin.x, y: top, width: screenWidth, height: height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: frameWidth, height: floatingToolbarSlotHeight)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        floatingToolbar

                        if showColorRow {
                            Color.clear
                                .frame(height: colorRowGapWorld)

                            CanvasCardColorSwatchRow(
                                activeColorHex: card.colorHex,
                                frameWidth: 280,
                                zoom: zoom,
                                cardColors: cardColors,
                                showCustomColorPicker: $showCustomColorPicker,
                                onSetColor: onSetColor
                            )
                            .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                        }
                    }
                    .scaleEffect(toolbarWorldScale, anchor: .top)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: frameWidth, alignment: .center)
                    .offset(y: pinnedToolbarTopY - floatingToolbarOffsetY)
                }
                .offset(y: floatingToolbarOffsetY)
                .animation(nil, value: showColorRow)
        }
        .frame(width: frameWidth, height: frameHeight, alignment: .topLeading)
        .allowsHitTesting(true)
    }

    private var floatingToolbar: some View {
        HStack(spacing: 3) {
            ToolbarIconButton(systemName: "trash", tip: "Delete", action: onDelete)
            ToolbarIconButton(systemName: "paintpalette", tip: "Set color", isActive: showColorRow) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { showColorRow.toggle() }
            }
            ToolbarIconButton(systemName: "viewfinder", tip: "Zoom to selection", action: onZoomToCard)

            if isImage {
                ToolbarIconButton(systemName: "square.and.pencil", tip: "Rename image", action: onRenameImage)
            } else {
                ToolbarIconButton(systemName: "square.and.pencil", tip: "Edit note", action: onBeginEditingNote)
            }
        }
        .padding(3)
        .background(AppColors.canvasBackground.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.floatingChromeShadow, radius: 10, y: 3)
        .fixedSize()
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private struct ToolbarIconButton: View {
        let systemName: String
        let tip: String
        var isActive: Bool = false
        let action: () -> Void
        @State private var hovered = false

        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 30, height: 26)
                    .foregroundStyle(
                        isActive
                            ? AppColors.selectionStroke
                            : (hovered ? AppColors.textPrimary : AppColors.textSecondary)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                isActive
                                    ? AppColors.selectionStroke.opacity(0.16)
                                    : (hovered ? AppColors.sidebarSelection : .clear)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            #if os(iOS)
            .canvasPencilToolbarHitTarget()
            #endif
            #if os(macOS)
            .onHover { hovered = $0 }
            #endif
            .help(tip)
        }
    }
}
