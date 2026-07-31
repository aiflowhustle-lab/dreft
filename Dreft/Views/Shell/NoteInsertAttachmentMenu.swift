import SwiftUI

#if os(iOS)
/// Where the insert-attachment popover should appear (Obsidian-style placement).
enum NoteInsertAttachmentMenuAnchor: Equatable {
    /// Canvas note card — menu below the card's left edge while editing.
    case canvasCard(screenRect: CGRect)
    /// Sidebar note — menu floats near the caret in the editor body.
    case noteEditor(topLeading: CGPoint)

    func menuTopLeading(menuSize: CGSize, containerSize: CGSize) -> CGPoint {
        let margin: CGFloat = 12
        let rawTopLeading: CGPoint
        switch self {
        case .canvasCard(let screenRect):
            rawTopLeading = CGPoint(
                x: screenRect.minX,
                y: screenRect.maxY + 8
            )
        case .noteEditor(let topLeading):
            rawTopLeading = topLeading
        }

        let maxX = max(margin, containerSize.width - menuSize.width - margin)
        let maxY = max(margin, containerSize.height - menuSize.height - margin)
        return CGPoint(
            x: min(max(margin, rawTopLeading.x), maxX),
            y: min(max(margin, rawTopLeading.y), maxY)
        )
    }

    func menuCenter(menuSize: CGSize, containerSize: CGSize) -> CGPoint {
        let origin = menuTopLeading(menuSize: menuSize, containerSize: containerSize)
        return CGPoint(
            x: origin.x + menuSize.width / 2,
            y: origin.y + menuSize.height / 2
        )
    }
}

/// Floating insert-attachment menu matching Obsidian iPad placement.
struct NoteInsertAttachmentMenuOverlay: View {
    @Binding var isPresented: Bool
    var anchor: NoteInsertAttachmentMenuAnchor?
    var onPhotoLibrary: () -> Void
    var onTakePhoto: () -> Void
    var onChooseFile: () -> Void

    private let menuSize = CGSize(width: 280, height: 152)

    var body: some View {
        if isPresented, let anchor {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isPresented = false
                        }

                    NoteInsertAttachmentMenu(
                        onPhotoLibrary: {
                            isPresented = false
                            onPhotoLibrary()
                        },
                        onTakePhoto: {
                            isPresented = false
                            onTakePhoto()
                        },
                        onChooseFile: {
                            isPresented = false
                            onChooseFile()
                        }
                    )
                    .frame(width: menuSize.width, height: menuSize.height, alignment: .topLeading)
                    .position(
                        anchor.menuCenter(
                            menuSize: menuSize,
                            containerSize: geometry.size
                        )
                    )
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
            .zIndex(500)
        }
    }
}

struct NoteInsertAttachmentMenu: View {
    var onPhotoLibrary: () -> Void
    var onTakePhoto: () -> Void
    var onChooseFile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            menuRow(icon: "photo.on.rectangle.angled", title: "Photo Library", action: onPhotoLibrary)
            menuRow(icon: "camera", title: "Take Photo or Video", action: onTakePhoto)
            menuRow(icon: "folder", title: "Choose File", action: onChooseFile)
        }
        .padding(.vertical, 6)
        .frame(width: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.overlayPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 10)
    }

    private func menuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 24, alignment: .center)

                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
