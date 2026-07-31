import SwiftUI

/// Tappable checkboxes aligned to task lines while editing a note card.
struct CanvasNoteCardTaskTapOverlay: View {
    let content: String
    let maxWidth: CGFloat
    let fontSize: CGFloat
    var scrollOffset: CGPoint = .zero
    var layoutPlacements: [NoteCardTaskCheckboxPlacement] = []
    var checkboxFillColor: Color = AppColors.noteCardBackground
    var onToggleTaskAtLine: (Int) -> Void

    private var lines: [NoteCardTextLine] {
        NoteCardTaskSupport.parsedLines(from: content)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if layoutPlacements.isEmpty {
                estimatedCheckboxOverlay
            } else {
                layoutCheckboxOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(x: -scrollOffset.x, y: 0)
    }

    @ViewBuilder
    private var layoutCheckboxOverlay: some View {
        ForEach(layoutPlacements) { placement in
            Button {
                onToggleTaskAtLine(placement.lineIndex)
            } label: {
                NoteCardTaskCheckbox(
                    checked: isTaskChecked(atLineIndex: placement.lineIndex),
                    fontSize: fontSize,
                    fillColor: checkboxFillColor
                )
            }
            .buttonStyle(.plain)
            .offset(x: placement.origin.x, y: placement.origin.y)
        }
    }

    @ViewBuilder
    private var estimatedCheckboxOverlay: some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            if case .task(let checked, _, _) = line {
                Button {
                    onToggleTaskAtLine(index)
                } label: {
                    NoteCardTaskCheckbox(
                        checked: checked,
                        fontSize: fontSize,
                        fillColor: checkboxFillColor
                    )
                }
                .buttonStyle(.plain)
                .offset(
                    x: max(0, (NoteCardTaskSupport.lineLeadingInset(fontSize: fontSize) - NoteCardTaskSupport.scaledCheckboxWidth(fontSize: fontSize)) / 2),
                    y: NoteCardTaskSupport.checkboxOriginY(
                        forLineIndex: index,
                        lines: lines,
                        fontSize: fontSize,
                        maxWidth: maxWidth
                    ) - scrollOffset.y + NoteCardTaskSupport.checkboxBaselineAlignmentOffset(fontSize: fontSize)
                )
            }
        }
    }

    private func isTaskChecked(atLineIndex index: Int) -> Bool {
        let parts = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard index >= 0, index < parts.count else { return false }
        guard let task = NoteCardTaskSupport.parseTaskLine(String(parts[index])),
              case .task(let checked, _, _) = task else { return false }
        return checked
    }
}
