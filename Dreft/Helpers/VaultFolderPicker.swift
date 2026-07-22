#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum VaultFolderPickerPurpose: Identifiable {
    case openVault
    case createLocation
    case reconnectVault(vaultID: String)

    var id: String {
        switch self {
        case .openVault: "openVault"
        case .createLocation: "createLocation"
        case .reconnectVault(let vaultID): "reconnectVault-\(vaultID)"
        }
    }
}

/// Presents the system folder picker reliably on iPad, including from modal overlays.
struct VaultFolderPickerSheet: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> FolderPickerHostViewController {
        let host = FolderPickerHostViewController()
        host.coordinator = context.coordinator
        return host
    }

    func updateUIViewController(_ uiViewController: FolderPickerHostViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

/// Host controller that presents `UIDocumentPickerViewController` modally so it works
/// from SwiftUI overlays and full-screen covers (not only nested sheets).
final class FolderPickerHostViewController: UIViewController {
    weak var coordinator: VaultFolderPickerSheet.Coordinator?
    private var didPresentPicker = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresentPicker else { return }
        didPresentPicker = true

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.delegate = coordinator
        picker.allowsMultipleSelection = false
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
    }
}

extension View {
    func vaultFolderPicker(
        purpose: Binding<VaultFolderPickerPurpose?>,
        onPick: @escaping (URL, VaultFolderPickerPurpose) -> Void
    ) -> some View {
        fullScreenCover(item: purpose) { activePurpose in
            VaultFolderPickerSheet(
                onPick: { url in
                    purpose.wrappedValue = nil
                    onPick(url, activePurpose)
                },
                onCancel: {
                    purpose.wrappedValue = nil
                }
            )
            .ignoresSafeArea()
            .background(Color.clear)
        }
    }
}
#endif
