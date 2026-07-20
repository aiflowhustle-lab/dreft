import SwiftUI

#if os(iOS)
/// iPad + Apple Pencil interaction sizing — finger navigates; pencil edits.
enum CanvasPencilInteraction {
    static let handleHitPixels: CGFloat = 44
    static let connectHitPixels: CGFloat = 44
    static let toolbarButtonSize: CGFloat = AppColors.minimumTouchTarget
    static let colorSwatchHitSize: CGFloat = AppColors.minimumTouchTarget
}

extension View {
    /// Expands the tappable area for toolbar controls without changing visual layout.
    func canvasPencilToolbarHitTarget() -> some View {
        frame(width: CanvasPencilInteraction.toolbarButtonSize, height: CanvasPencilInteraction.toolbarButtonSize)
            .contentShape(Rectangle())
    }
}
#endif
