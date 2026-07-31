import SwiftUI

/// Obsidian-style empty/checked box used in note-card previews.
struct NoteCardTaskCheckbox: View {
    let checked: Bool
    var fontSize: CGFloat = CanvasConstants.noteCardFontSize
    var fillColor: Color = AppColors.noteCardBackground

    private var boxSize: CGFloat {
        NoteCardTaskSupport.scaledCheckboxWidth(fontSize: fontSize)
    }

    private var cornerRadius: CGFloat {
        max(3, boxSize * 0.25)
    }

    private var checkmarkSize: CGFloat {
        max(8, boxSize * 0.6)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AppColors.textSecondary.opacity(0.85), lineWidth: 1.5)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fillColor)
                )
                .frame(width: boxSize, height: boxSize)

            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: checkmarkSize, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .frame(width: boxSize, height: boxSize)
    }
}
