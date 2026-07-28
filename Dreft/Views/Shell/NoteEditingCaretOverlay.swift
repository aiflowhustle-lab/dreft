import SwiftUI

/// Draws a visible caret and selection highlights over native text views when the
/// system insertion point is hidden (canvas cards with image embeds).
struct NoteEditingCaretOverlay: View {
    let caretRect: CGRect
    let selectionRects: [CGRect]
    let fontSize: CGFloat
    let isVisible: Bool

    @State private var caretVisible = true

    private var caretHeight: CGFloat {
        max(4, min(caretRect.height > 1 ? caretRect.height : fontSize * 1.15, fontSize * 1.35))
    }

    private var hasMeasuredCaret: Bool {
        caretRect.height > 0.5 || caretRect.width > 0.5 || caretRect.maxX > 0.5 || caretRect.maxY > 0.5
    }

    private var caretPosition: CGPoint {
        if hasMeasuredCaret {
            return CGPoint(x: caretRect.minX + 1, y: caretRect.midY)
        }
        return CGPoint(x: 2, y: fontSize * 0.65 + 2)
    }

    private var showsCaret: Bool {
        isVisible && selectionRects.isEmpty
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(selectionRects.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppColors.selectionStroke.opacity(0.24))
                    .frame(width: max(2, rect.width), height: max(4, rect.height))
                    .position(x: rect.midX, y: rect.midY)
            }

            if showsCaret {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(AppColors.textPrimary)
                    .frame(width: 2, height: caretHeight)
                    .position(x: caretPosition.x, y: caretPosition.y)
                    .opacity(caretVisible ? 1 : 0.15)
            }
        }
        .allowsHitTesting(false)
        .task(id: isVisible) {
            guard isVisible else { return }
            caretVisible = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                caretVisible.toggle()
            }
        }
    }
}
