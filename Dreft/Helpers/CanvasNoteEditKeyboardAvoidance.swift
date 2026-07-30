import CoreGraphics

/// Keeps a canvas note card above the iPad keyboard + formatting accessory while editing.
enum CanvasNoteEditKeyboardAvoidance {
    static let bottomPadding: CGFloat = 24
    static let topSafeInset: CGFloat = 16

    /// Used before UIKit reports keyboard frame so the card starts moving immediately.
    static let estimatedKeyboardOverlap: CGFloat = 380

    /// Total bottom obstruction (keyboard + accessory toolbar + padding).
    static func requiredPanDeltaY(
        cardScreenRect: CGRect,
        canvasHeight: CGFloat,
        bottomObstructionHeight: CGFloat
    ) -> CGFloat {
        guard bottomObstructionHeight > 0, canvasHeight > 0 else { return 0 }

        let availableBottom = canvasHeight - bottomObstructionHeight - bottomPadding
        var pan = max(0, cardScreenRect.maxY - availableBottom)

        // Tall cards: pull the card up far enough to keep the top in view while editing.
        let visibleHeight = max(0, availableBottom - topSafeInset)
        if cardScreenRect.height > visibleHeight {
            pan = max(pan, cardScreenRect.minY - topSafeInset)
        }

        return pan
    }
}
