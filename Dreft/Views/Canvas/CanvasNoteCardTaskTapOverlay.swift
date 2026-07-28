import SwiftUI

/// Tappable checkboxes aligned to task lines while editing a note card.
struct CanvasNoteCardTaskTapOverlay: View {
    let content: String
    let maxWidth: CGFloat
    let fontSize: CGFloat
    var scrollOffset: CGPoint = .zero
    var onToggleTaskRawLine: (String) -> Void

    private var lines: [NoteCardTextLine] {
        NoteCardTaskSupport.parsedLines(from: content)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if case .task(let checked, _, let rawLine) = line {
                    Button {
                        onToggleTaskRawLine(rawLine)
                    } label: {
                        NoteCardTaskCheckbox(checked: checked)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, max(2, fontSize * 0.12))
                    .offset(
                        x: 0,
                        y: NoteCardTaskSupport.checkboxOriginY(
                            forLineIndex: index,
                            lines: lines,
                            fontSize: fontSize,
                            maxWidth: maxWidth
                        ) - scrollOffset.y
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(x: -scrollOffset.x, y: 0)
    }
}
