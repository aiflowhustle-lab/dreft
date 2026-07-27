import SwiftUI

struct CanvasNoteScrollMetrics: Equatable {
    var offset: CGPoint = .zero
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    var showsIndicator: Bool {
        contentHeight > viewportHeight + 2
    }
}

/// Obsidian-style thin overlay scrollbar drawn above card content (not behind images).
struct CanvasNoteCardScrollIndicator: View {
    let metrics: CanvasNoteScrollMetrics

    private let trackWidth: CGFloat = 5
    private let trackInset: CGFloat = 4
    private let thumbMinHeight: CGFloat = 28

    var body: some View {
        if metrics.showsIndicator, metrics.viewportHeight > 0 {
            let viewport = metrics.viewportHeight
            let thumbHeight = max(
                thumbMinHeight,
                viewport * (viewport / max(metrics.contentHeight, 1))
            )
            let trackRange = max(0, viewport - thumbHeight)
            let maxOffset = max(1, metrics.contentHeight - viewport)
            let thumbY = trackRange * (max(0, metrics.offset.y) / maxOffset)

            RoundedRectangle(cornerRadius: trackWidth / 2, style: .continuous)
                .fill(AppColors.textSecondary.opacity(0.42))
                .frame(width: trackWidth, height: thumbHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, trackInset)
                .offset(y: thumbY)
                .allowsHitTesting(false)
        }
    }
}

private struct NoteCardPreviewContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NoteCardPreviewScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func noteCardPreviewContentHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: NoteCardPreviewContentHeightKey.self,
                    value: geometry.size.height
                )
            }
        }
        .onPreferenceChange(NoteCardPreviewContentHeightKey.self, perform: onChange)
    }

    func noteCardPreviewScrollOffset(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: NoteCardPreviewScrollOffsetKey.self,
                    value: geometry.frame(in: .named("noteCardPreviewScroll")).minY
                )
            }
        }
        .onPreferenceChange(NoteCardPreviewScrollOffsetKey.self, perform: onChange)
    }
}
