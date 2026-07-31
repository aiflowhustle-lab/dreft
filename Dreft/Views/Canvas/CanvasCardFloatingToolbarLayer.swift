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

    private var gapAboveCard: CGFloat {
        CanvasFloatingToolbarChrome.gapAboveCard
    }

    private var colorRowLayoutHeight: CGFloat { 28 }
    private var colorRowGap: CGFloat { 5 }

    /// Screen-space rect for hit-testing — keeps toolbar clicks from starting edge drags / dismiss taps.
    static func screenHitRect(
        worldFrame: CGRect,
        zoom: CGFloat,
        showColorRow: Bool,
        worldToScreen: (CGPoint) -> CGPoint
    ) -> CGRect {
        let origin = worldToScreen(worldFrame.origin)
        let screenWidth = worldFrame.width * zoom
        let slotHeight = CanvasFloatingToolbarChrome.toolbarSlotHeight(showColorRow: showColorRow)
        return CGRect(
            x: origin.x,
            y: origin.y - slotHeight,
            width: screenWidth,
            height: slotHeight
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            floatingToolbar

            if showColorRow {
                Color.clear.frame(height: colorRowGap)

                CanvasCardColorSwatchRow(
                    activeColorHex: card.colorHex,
                    frameWidth: frameWidth,
                    zoom: zoom,
                    cardColors: cardColors,
                    showCustomColorPicker: $showCustomColorPicker,
                    onSetColor: onSetColor
                )
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }

            Color.clear.frame(height: gapAboveCard)
        }
        .frame(width: frameWidth, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .animation(nil, value: showColorRow)
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
            .accessibilityLabel(tip)
        }
    }
}
