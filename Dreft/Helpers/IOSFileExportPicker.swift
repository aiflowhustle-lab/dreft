#if os(iOS)
import SwiftUI
import UIKit

struct IOSPendingFileExport: Identifiable {
    let id = UUID()
    let url: URL
}

/// Lets the user pick a save location in the Files app for an exported file.
struct IOSFileExportPicker: UIViewControllerRepresentable {
    let fileURL: URL
    let onComplete: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> ExportPickerHostViewController {
        let host = ExportPickerHostViewController(fileURL: fileURL)
        host.coordinator = context.coordinator
        return host
    }

    func updateUIViewController(_ uiViewController: ExportPickerHostViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: (URL?) -> Void

        init(onComplete: @escaping (URL?) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(nil)
        }
    }
}

final class ExportPickerHostViewController: UIViewController {
    let fileURL: URL
    weak var coordinator: IOSFileExportPicker.Coordinator?
    private var didPresentPicker = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresentPicker else { return }
        didPresentPicker = true

        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = coordinator
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
    }
}

enum IOSShareSheet {
    static func present(fileURL: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? scene.windows.first?.rootViewController else { return }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }

        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = top.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(
            x: top.view.bounds.midX,
            y: top.view.bounds.midY,
            width: 1,
            height: 1
        )
        activityVC.popoverPresentationController?.permittedArrowDirections = []
        top.present(activityVC, animated: true)
    }
}
#endif
