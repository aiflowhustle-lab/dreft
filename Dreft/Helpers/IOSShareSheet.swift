#if os(iOS)
import UIKit

/// Presents the system share sheet for a file URL from the topmost view controller.
enum IOSShareSheet {
    static func present(fileURL: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController else { return }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }

        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        // iPad requires a popover anchor.
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
