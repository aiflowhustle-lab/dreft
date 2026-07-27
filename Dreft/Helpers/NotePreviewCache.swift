import Foundation
import SwiftUI

/// Caches rendered note previews so undo/redo does not re-parse markdown for every card.
enum NotePreviewCache {
    private static let rendererVersion = 3
    private static var cache: [String: AttributedString] = [:]
    private static var order: [String] = []
    private static let maxEntries = 96

    private static func cacheKey(for content: String) -> String {
        "\(rendererVersion)|\(content)"
    }

    static func canvasCardPreview(for content: String) -> AttributedString {
        let key = cacheKey(for: content)
        if let cached = cache[key] {
            return cached
        }

        let rendered = NoteMarkdownRenderer.canvasCardPreviewAttributedString(from: content)
        cache[key] = rendered
        order.append(key)
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
