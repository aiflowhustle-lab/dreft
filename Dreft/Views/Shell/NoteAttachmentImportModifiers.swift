#if os(iOS)
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Shared iOS attachment-import modifiers for sidebar notes and canvas card editing.
struct NoteAttachmentImportModifiers: ViewModifier {
    @Binding var showAttachmentMenu: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var showFileImporter: Bool
    @Binding var photoItem: PhotosPickerItem?
    var menuAnchor: () -> NoteInsertAttachmentMenuAnchor?
    var presentsMenuOverlay: Bool
    var onInsertImage: (Data, String?) -> Void
    var onImportFile: (Result<[URL], Error>) -> Void
    var onRegisterInsertAttachment: () -> Void

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    defer {
                        Task { @MainActor in
                            photoItem = nil
                        }
                    }
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    await MainActor.run {
                        onInsertImage(data, item.itemIdentifier)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker(
                    onImage: { data in
                        onInsertImage(data, "photo.jpg")
                    },
                    onCancel: {
                        showCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .overlay {
                if presentsMenuOverlay {
                    NoteInsertAttachmentMenuOverlay(
                        isPresented: $showAttachmentMenu,
                        anchor: showAttachmentMenu ? menuAnchor() : nil,
                        onPhotoLibrary: { showPhotoPicker = true },
                        onTakePhoto: { showCamera = true },
                        onChooseFile: { showFileImporter = true }
                    )
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                onImportFile(result)
            }
            .onAppear(perform: onRegisterInsertAttachment)
    }
}

extension View {
    func noteAttachmentImportModifiers(
        showAttachmentMenu: Binding<Bool>,
        showPhotoPicker: Binding<Bool>,
        showCamera: Binding<Bool>,
        showFileImporter: Binding<Bool>,
        photoItem: Binding<PhotosPickerItem?>,
        menuAnchor: @escaping () -> NoteInsertAttachmentMenuAnchor?,
        presentsMenuOverlay: Bool = true,
        onInsertImage: @escaping (Data, String?) -> Void,
        onImportFile: @escaping (Result<[URL], Error>) -> Void,
        onRegisterInsertAttachment: @escaping () -> Void
    ) -> some View {
        modifier(
            NoteAttachmentImportModifiers(
                showAttachmentMenu: showAttachmentMenu,
                showPhotoPicker: showPhotoPicker,
                showCamera: showCamera,
                showFileImporter: showFileImporter,
                photoItem: photoItem,
                menuAnchor: menuAnchor,
                presentsMenuOverlay: presentsMenuOverlay,
                onInsertImage: onInsertImage,
                onImportFile: onImportFile,
                onRegisterInsertAttachment: onRegisterInsertAttachment
            )
        )
    }
}
#endif
