import Foundation

/// Resolves what a canvas note card displays and whether `content` is a vault path or inline markdown.
enum CanvasCardContent {
    /// True when `content` looks like a vault-relative note path (Obsidian JSON Canvas `file` nodes).
    static func isVaultNotePath(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return false }
        guard !trimmed.hasPrefix("#") else { return false }
        let ext = (trimmed as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    static func linkedNotePath(for card: CanvasCard) -> String? {
        guard card.kind == .note, isVaultNotePath(card.content) else { return nil }
        return card.content
    }

    /// Markdown body shown in previews and the edit overlay.
    static func markdownBody(
        for card: CanvasCard,
        vaultURL: URL?,
        vaultFiles: [VaultFile] = []
    ) -> String {
        guard card.kind == .note || card.kind == .text else { return card.content }
        if let path = linkedNotePath(for: card) {
            if let file = vaultFiles.first(where: { $0.relativePath == path }),
               let content = file.noteContent,
               !content.isEmpty {
                return content
            }
            if let vaultURL,
               let content = VaultFilesystem.readNoteContent(relativePath: path, vaultURL: vaultURL),
               !content.isEmpty {
                return content
            }
            let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return "# \(title)\n"
        }
        return card.content
    }
}
