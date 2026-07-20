import SwiftUI

/// Obsidian-style iPad canvas toolbar — sections on the right, draggable vertically.
struct CanvasIPadRightToolbar: View {
    let canvasSize: CGSize
    let sidebarVisible: Bool
    let canUndo: Bool
    let canRedo: Bool
    let canZoomIn: Bool
    let canZoomOut: Bool

    var onSettings: () -> Void
    var onZoomIn: () -> Void
    var onResetZoom: () -> Void
    var onZoomToFit: () -> Void
    var onZoomOut: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void

    @AppStorage("canvasToolbarDragY") private var storedDragY: Double = 0
    @State private var dragYOffset: CGFloat = 0

    private let sectionWidth: CGFloat = 46
    private let buttonSize: CGFloat = 44
    private let iconSize: CGFloat = 14
    private let expandIconSize: CGFloat = 18
    private let sectionGap: CGFloat = 4
    private let cornerRadius: CGFloat = 10
    /// Inset from the right screen edge so controls aren't clipped or hard to tap.
    private let trailingInset: CGFloat = 12

    /// gear + 4 zoom + 2 history buttons, paddings and gaps
    private var stackHeight: CGFloat {
        buttonSize * 7 + 4 * 6 + sectionGap * 2
    }

    var body: some View {
        toolbarSections
            .offset(y: baseTopInset + clampedDragY)
            .gesture(toolbarDragGesture)
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topTrailing)
            .onAppear {
                dragYOffset = CGFloat(storedDragY)
            }
    }

    private var baseTopInset: CGFloat { 6 }

    private var clampedDragY: CGFloat {
        let maxDown = max(0, canvasSize.height - stackHeight - baseTopInset - 52)
        return min(max(0, dragYOffset), maxDown)
    }

    // MARK: - Toolbar sections (gear / zoom / undo-redo)

    private var toolbarSections: some View {
        VStack(alignment: .trailing, spacing: sectionGap) {
            edgeSection {
                toolButton("gearshape", tip: "Canvas settings", action: onSettings)
            }

            edgeSection {
                VStack(spacing: 0) {
                    toolButton("plus", tip: "Zoom in", enabled: canZoomIn, action: onZoomIn)
                    toolButton("arrow.clockwise", tip: "Reset zoom", action: onResetZoom)
                    toolButton(
                        "arrow.up.left.and.arrow.down.right",
                        tip: "Zoom to fit",
                        iconSize: expandIconSize,
                        iconWeight: .semibold,
                        action: onZoomToFit
                    )
                    toolButton("minus", tip: "Zoom out", enabled: canZoomOut, action: onZoomOut)
                }
            }

            edgeSection {
                VStack(spacing: 0) {
                    toolButton("arrow.uturn.backward", tip: "Undo", enabled: canUndo, action: onUndo)
                    toolButton("arrow.uturn.forward", tip: "Redo", enabled: canRedo, action: onRedo)
                }
            }
        }
        .padding(.trailing, trailingInset)
    }

    private func edgeSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content()
            .padding(.vertical, 2)
            .padding(.leading, 1)
            .frame(width: sectionWidth + 1)
            .background {
                ZStack {
                    shape.fill(.thinMaterial)
                    shape.fill(AppColors.floatingChrome)
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(AppColors.floatingChromeBorder, lineWidth: 1))
            .shadow(color: AppColors.floatingChromeShadow, radius: 8, y: 2)
    }

    private func toolButton(
        _ name: String,
        tip: String,
        enabled: Bool = true,
        iconSize: CGFloat? = nil,
        iconWeight: Font.Weight = .regular,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: iconSize ?? self.iconSize, weight: iconWeight))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(AppColors.textPrimary.opacity(enabled ? 0.88 : 0.3))
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(CanvasIPadToolButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(tip)
    }

    private var toolbarDragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let proposed = CGFloat(storedDragY) + value.translation.height
                let maxDown = max(0, canvasSize.height - stackHeight - baseTopInset - 52)
                dragYOffset = min(max(0, proposed), maxDown)
            }
            .onEnded { _ in
                storedDragY = Double(dragYOffset)
            }
    }
}

private struct CanvasIPadToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? AppColors.toolbarButtonPressed : Color.clear)
            )
    }
}
