import CoreGraphics

/// Keeps a canvas note card above the iPad keyboard + formatting accessory while editing.
enum CanvasNoteEditKeyboardAvoidance {
    static let bottomPadding: CGFloat = 16
    static let topSafeInset: CGFloat = 16
    /// Space to keep below the caret line when panning.
    static let caretLinePadding: CGFloat = 28

    /// Total bottom obstruction (keyboard + accessory toolbar + padding).
    static func requiredPanDeltaY(
        cardScreenRect: CGRect,
        caretScreenY: CGFloat?,
        canvasHeight: CGFloat,
        bottomObstructionHeight: CGFloat,
        cardToolbarScreenHeight: CGFloat = 50
    ) -> CGFloat {
        guard bottomObstructionHeight > 0, canvasHeight > 0 else { return 0 }

        let availableBottom = canvasHeight - bottomObstructionHeight - bottomPadding
        let editAnchorY = (caretScreenY ?? cardScreenRect.maxY) + caretLinePadding
        let pan = max(0, editAnchorY - availableBottom)

        // Never pan so far that the card's floating toolbar (delete / color / zoom) clips off the top.
        let minCardTop = topSafeInset + cardToolbarScreenHeight
        let maxPan = max(0, cardScreenRect.minY - minCardTop)
        return min(pan, maxPan)
    }
}
