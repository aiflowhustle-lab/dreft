import SwiftUI

/// Manual vertical scroller for selected note-card preview — same wheel/touch path as edit mode.
struct CanvasNoteCardPreviewScrollContainer<Content: View>: View {
    @Binding var offsetY: CGFloat
    @Binding var contentHeight: CGFloat
    let viewportHeight: CGFloat
    var onTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @State private var dragOriginOffset: CGFloat = 0
    @State private var isDragging = false

    private var maxOffset: CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content()
                .noteCardPreviewContentHeight { height in
                    scheduleContentHeight(height)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .offset(y: -offsetY)
        }
        .frame(height: viewportHeight, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .highPriorityGesture(previewDragGesture)
        .onAppear {
            dragOriginOffset = offsetY
            registerScrollBridge()
        }
        .onDisappear {
            unregisterScrollBridge()
        }
        .onChange(of: viewportHeight) { _, _ in
            Task { @MainActor in
                clampOffset()
            }
        }
    }

    private func scheduleContentHeight(_ height: CGFloat) {
        guard abs(contentHeight - height) > 0.5 else { return }
        Task { @MainActor in
            contentHeight = height
            clampOffset()
        }
    }

    private var previewDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = abs(value.translation.width)
                let dy = abs(value.translation.height)
                guard maxOffset > 0.5 else { return }
                guard isDragging || dy >= dx else { return }

                if !isDragging {
                    isDragging = true
                    dragOriginOffset = offsetY
                }
                let proposed = dragOriginOffset - value.translation.height
                offsetY = min(max(0, proposed), maxOffset)
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) > 3
                if !moved {
                    onTap?()
                }
                isDragging = false
                dragOriginOffset = offsetY
            }
    }

    private func clampOffset() {
        let clamped = min(max(0, offsetY), maxOffset)
        if clamped != offsetY {
            offsetY = clamped
        }
        dragOriginOffset = clamped
    }

    private func registerScrollBridge() {
        CanvasNoteCardScrollBridge.register(owner: "preview") { delta in
            applyWheelDelta(delta)
        }
    }

    private func unregisterScrollBridge() {
        CanvasNoteCardScrollBridge.unregister(owner: "preview")
    }

    private func applyWheelDelta(_ delta: CGSize) -> CanvasNoteScrollConsumption {
        if maxOffset > 0 {
            let clamped = CanvasNoteCardScrollMath.clampedOffset(
                current: offsetY,
                delta: delta.height,
                maxOffset: maxOffset
            )
            offsetY = clamped.offset
            dragOriginOffset = clamped.offset
        }
        return .absorbed
    }
}
