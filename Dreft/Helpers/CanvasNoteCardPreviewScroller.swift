import SwiftUI

/// Manual vertical scroller for selected note-card preview — same wheel/touch path as edit mode.
struct CanvasNoteCardPreviewScrollContainer<Content: View>: View {
    @Binding var offsetY: CGFloat
    @Binding var contentHeight: CGFloat
    let viewportHeight: CGFloat
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
        .gesture(previewDragGesture)
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
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragOriginOffset = offsetY
                }
                let proposed = dragOriginOffset - value.translation.height
                offsetY = min(max(0, proposed), maxOffset)
            }
            .onEnded { _ in
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
