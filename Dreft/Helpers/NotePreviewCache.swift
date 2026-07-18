import Foundation
import SwiftUI

/// Caches rendered note previews so undo/redo does not re-parse markdown for every card.
enum NotePreviewCache {
    private static var cache: [String: AttributedString] = [:]
    private static var order: [String] = []
    private static let maxEntries = 96

    static func canvasCardPreview(for content: String) -> AttributedString {
        if let cached = cache[content] {
            return cached
        }

        let rendered = NoteMarkdownRenderer.previewAttributedString(from: content)
        cache[content] = rendered
        order.append(content)
        if order.count > maxEntries, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        return rendered
    }

    static func invalidateAll() {
        cache.removeAll()
        order.removeAll()
    }
}
