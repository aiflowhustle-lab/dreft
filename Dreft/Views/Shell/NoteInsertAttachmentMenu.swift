import SwiftUI

#if os(iOS)
/// Floating insert-attachment menu matching the iPad note reference design.
struct NoteInsertAttachmentMenuOverlay: View {
    @Binding var isPresented: Bool
    var onPhotoLibrary: () -> Void
    var onTakePhoto: () -> Void
    var onChooseFile: () -> Void

    var body: some View {
        if isPresented {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 40)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
