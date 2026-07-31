import CoreGraphics
import Foundation

/// Shared image-embed insert path for sidebar notes and canvas card editing.
enum NoteAttachmentInsertSupport {
    struct PreparedInsert {
        let text: String
        let selectedRange: NSRange
    }

    /// Saves image data to the vault, caches display metrics, and returns the vault-relative path.
    static func saveImage(
        data: Data,
        suggestedName: String?,
        vaultURL: URL,
        maxWidth: CGFloat
    ) -> String? {
        guard let path = try? VaultFilesystem.saveCanvasImage(
            data: data,
            vaultURL: vaultURL,
            suggestedName: suggestedName
        ) else { return nil }

        let displaySize = displaySize(for: data, maxWidth: maxWidth)
        NoteCardEmbedLayoutMetrics.store(height: displaySize.height, path: path, maxWidth: maxWidth)

        Task {
            await CanvasImageCache.shared.prepareDisplayImage(
                data: data,
                cardID: "note-embed|\(path)",
                contentKey: path
            )
        }
        return path
    }

    private static func displaySize(for data: Data, maxWidth: CGFloat) -> CGSize {
        if let pixelSize = ImagePixelSize.from(data: data) {
            return NoteCardInlineImageMetrics.displaySize(forPixelSize: pixelSize, maxWidth: maxWidth)
        }
        return CGSize(width: min(maxWidth, 160), height: min(maxWidth * 0.6, 120))
    }

    /// Normalizes, inserts, sanitizes, and places the caret below a fresh image embed.
    static func prepareEmbedInsert(
        path: String,
        in text: String,
        selectedRange: NSRange,
        vaultURL: URL?
    ) -> PreparedInsert {
        let snippet = "![[\(path)]]"
        let normalized = NoteCardEmbedEditingSupport.normalizedAttachmentSnippet(
            snippet,
            in: text,
            range: selectedRange
        )
        let inserted = MarkdownEditingSupport.insertText(normalized, in: text, range: selectedRange)
        let sanitized = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(
            in: inserted.text,
            vaultURL: vaultURL,
            selectedRange: inserted.selectedRange
        )
        var range = sanitized.selectedRange ?? inserted.selectedRange
        if snippet.hasPrefix("![["),
           let caret = NoteCardEmbedEditingSupport.caretBelowLastImageEmbed(in: sanitized.text, vaultURL: vaultURL) {
            range = caret
        }
        return PreparedInsert(text: sanitized.text, selectedRange: range)
    }
}
