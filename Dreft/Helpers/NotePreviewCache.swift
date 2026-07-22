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

    /// Plain first-line stub for summary LOD — no markdown parsing.
    static func summaryLine(for content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var line = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        while line.hasPrefix("#") {
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespaces)
        }
        line = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return "" }
        if line.count > 72 {
            return String(line.prefix(72)) + "…"
        }
        return line
    }

    static func invalidateAll() {
        cache.removeAll()
        order.removeAll()
    }
}
