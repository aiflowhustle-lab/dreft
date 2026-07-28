import SwiftUI

/// Obsidian-style empty/checked box used in note-card previews.
struct NoteCardTaskCheckbox: View {
    let checked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(AppColors.textSecondary.opacity(0.85), lineWidth: 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(AppColors.noteCardBackground)
                )
                .frame(width: 14, height: 14)

            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .frame(width: 14, height: 14)
    }
}
