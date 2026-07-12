import SwiftUI

/// Obsidian-style iPad canvas toolbar — sections attached flush to the right
/// screen edge (rounded on the left only), draggable vertically and
/// collapsible into a curved edge tab.
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

    @AppStorage("canvasToolbarCollapsed") private var isCollapsed = false
    @AppStorage("canvasToolbarDragY") private var storedDragY: Double = 0
    @State private var dragYOffset: CGFloat = 0

    private let sectionWidth: CGFloat = 40
    private let buttonSize: CGFloat = 38
    private let iconSize: CGFloat = 15
    private let sectionGap: CGFloat = 6
    private let cornerRadius: CGFloat = 12

    /// gear + 4 zoom + 2 history buttons, paddings and gaps
    private var stackHeight: CGFloat {
        buttonSize * 7 + 8 * 6 + sectionGap * 2
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isCollapsed {
                collapseHandle
            } else {
                toolbarSections
                    .offset(y: baseTopInset + clampedDragY)
                    .gesture(toolbarDragGesture)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topTrailing)
        .onAppear {
            dragYOffset = CGFloat(storedDragY)
        }
    }

    private var baseTopInset: CGFloat { 14 }

    private var clampedDragY: CGFloat {
        let maxDown = max(0, canvasSize.height - stackHeight - baseTopInset - 60)
        return min(max(0, dragYOffset), maxDown)
    }

    // MARK: - Edge-attached sections (references: gear / zoom / undo-redo)

    private var toolbarSections: some View {
        VStack(alignment: .trailing, spacing: sectionGap) {
            edgeSection {
                toolButton("gearshape", tip: "Canvas settings", action: onSettings)
            }

            edgeSection {
                VStack(spacing: 0) {
                    toolButton("plus", tip: "Zoom in", enabled: canZoomIn, action: onZoomIn)
                    toolButton("arrow.clockwise", tip: "Reset zoom", action: onResetZoom)
                    toolButton("arrow.up.left.and.arrow.down.right", tip: "Zoom to fit", action: onZoomToFit)
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isCollapsed = true
                }
            }
        )
    }

    /// Section flush to the right edge — rounded corners on the left side only.
    private func edgeSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
        return content()
            .padding(.vertical, 4)
            .padding(.leading, 2)
            .frame(width: sectionWidth + 2)
            .background {
                ZStack {
                    shape.fill(.thinMaterial)
                    shape.fill(AppColors.floatingChrome)
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(AppColors.floatingChromeBorder, lineWidth: 1))
            .shadow(color: AppColors.floatingChromeShadow, radius: 10, y: 3)
    }

    private func toolButton(
        _ name: String,
        tip: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: iconSize, weight: .regular))
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
                let maxDown = max(0, canvasSize.height - stackHeight - baseTopInset - 60)
                dragYOffset = min(max(0, proposed), maxDown)
            }
            .onEnded { _ in
                storedDragY = Double(dragYOffset)
            }
    }

    // MARK: - Collapsed edge tab (curved handle, bottom-right)

    private var collapseHandle: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isCollapsed = false
            }
        } label: {
            CanvasToolbarEdgeTabShape()
                .fill(AppColors.floatingChrome)
                .overlay(CanvasToolbarEdgeTabShape().stroke(AppColors.floatingChromeBorder, lineWidth: 1))
                .overlay(
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .offset(x: 4)
                )
                .frame(width: 22, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.bottom, 96)
    }
}

private struct CanvasIPadToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? AppColors.toolbarButtonPressed : Color.clear)
            )
    }
}

private struct CanvasToolbarEdgeTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.28),
            control: CGPoint(x: w * 0.1, y: h * 0.06)
        )
        path.addLine(to: CGPoint(x: 0, y: h * 0.72))
        path.addQuadCurve(
            to: CGPoint(x: w, y: h),
            control: CGPoint(x: w * 0.1, y: h * 0.94)
        )
        path.closeSubpath()
        return path
    }
}
