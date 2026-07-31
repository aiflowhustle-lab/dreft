import Foundation

enum CanvasAccessibility {
    static func cardLabel(for card: CanvasCard, isSelected: Bool) -> String {
        let kindName: String = switch card.kind {
        case .image: "Image"
        case .note: "Note"
        case .text: "Text"
        }
        let trimmedTitle = card.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmedTitle.isEmpty ? kindName : trimmedTitle
        return isSelected ? "\(name), selected" : name
    }

    static func cardHint(for card: CanvasCard) -> String {
        switch card.kind {
        case .image:
            "Drag to move. Use the toolbar to rename or delete."
        case .note, .text:
            "Drag to move. Double tap to edit."
        }
    }

    static func canvasLabel(zoomPercent: Int, cardCount: Int) -> String {
        "Canvas, \(cardCount) cards, zoom \(zoomPercent) percent"
    }
}
