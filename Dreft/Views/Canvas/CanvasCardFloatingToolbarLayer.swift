import SwiftUI

/// Floating card toolbar rendered in screen space above connection lines.
struct CanvasCardFloatingToolbarLayer: View {
    let card: CanvasCard
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let zoom: CGFloat
    @Binding var showColorRow: Bool

    var onDelete: () -> Void
    var onZoomToCard: () -> Void
    var onBeginEditingNote: () -> Void

    private var isImage: Bool { card.kind == .image }

    private var toolbarLayoutHeight: CGFloat { 38 }
    private var toolbarGapAboveCard: CGFloat { 12 }

    private var toolbarWorldScale: CGFloat {
        let clampedZoom = min(max(zoom, 0.45), 1.35)
        return 1 / clampedZoom
    }

    private var floatingToolbarSlotHeight: CGFloat {
        (toolbarLayoutHeight + toolbarGapAboveCard) * toolbarWorldScale
    }

    private var floatingToolbarOffsetY: CGFloat {
        -floatingToolbarSlotHeight
    }

    /// Screen-space rect for hit-testing — keeps toolbar clicks from starting edge drags / dismiss taps.
    static func screenHitRect(
        worldFrame: CGRect,
        zoom: CGFloat,
        worldToScreen: (CGPoint) -> CGPoint
    ) -> CGRect {
        let toolbarWorldScale = 1 / min(max(zoom, 0.45), 1.35)
        let slotHeight = (38 + 12) * toolbarWorldScale
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
                .overlay(alignment: .bottom) {
                    floatingToolbar
                        .scaleEffect(toolbarWorldScale, anchor: .bottom)
                        .padding(.bottom, toolbarGapAboveCard * toolbarWorldScale)
                        .frame(width: frameWidth, alignment: .center)
                }
                .offset(y: floatingToolbarOffsetY)
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
            if !isImage {
                ToolbarIconButton(systemName: "square.and.pencil", tip: "Edit note", action: onBeginEditingNote)
            }
        }
        .padding(3)
        .background(AppColors.canvasBackground.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
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
                            : (hovered ? Color.white.opacity(0.92) : AppColors.textSecondary)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                isActive
                                    ? AppColors.selectionStroke.opacity(0.16)
                                    : (hovered ? Color.white.opacity(0.07) : .clear)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .help(tip)
        }
    }
}
