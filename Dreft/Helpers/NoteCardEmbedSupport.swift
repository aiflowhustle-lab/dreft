import Foundation

enum NoteCardContentSegment: Equatable {
    case text(String)
    case image(vaultPath: String)
}

enum NoteCardEmbedSupport {
    /// Obsidian-style embeds (`![[file.jpg]]`) and image wikilinks (`[[file.jpg]]`).
    private static let embedPattern = #"!?\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#

    static func segments(from content: String, vaultURL: URL?) -> [NoteCardContentSegment] {
        guard let regex = try? NSRegularExpression(pattern: embedPattern) else {
            return content.isEmpty ? [] : [.text(content)]
        }

        let ns = content as NSString
        var segments: [NoteCardContentSegment] = []
        var cursor = 0
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: ns.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let range = match.range
            if range.location > cursor {
                appendText(ns.substring(with: NSRange(location: cursor, length: range.location - cursor)), to: &segments)
            }

            let target = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if VaultFilesystem.isImageEmbedTarget(target) {
                let path = VaultFilesystem.preferredCanvasAssetPath(for: target)
                segments.append(.image(vaultPath: path))
            } else {
                appendText(ns.substring(with: range), to: &segments)
            }

            cursor = range.location + range.length
        }

        if cursor < ns.length {
            appendText(ns.substring(from: cursor), to: &segments)
        }

        return segments
    }

    static func imagePaths(from content: String, vaultURL: URL?) -> [String] {
        segments(from: content, vaultURL: vaultURL).compactMap { segment in
            if case .image(let vaultPath) = segment { return vaultPath }
            return nil
        }
    }

    private static func appendText(_ chunk: String, to segments: inout [NoteCardContentSegment]) {
        guard !chunk.isEmpty else { return }
        if case .text(let existing)? = segments.last {
            segments[segments.count - 1] = .text(existing + chunk)
        } else {
            segments.append(.text(chunk))
        }
    }

    /// Image embed markdown ranges (`![[photo.jpg]]` or `[[photo.jpg]]`) in source order.
    static func imageEmbedRanges(in content: String, vaultURL: URL?) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: embedPattern) else { return [] }
        let ns = content as NSString
        return regex.matches(in: content, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let target = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard VaultFilesystem.isImageEmbedTarget(target) else { return nil }
            return match.range
        }
    }
}

enum NoteCardEmbedEditingSupport {
    /// On the line above a hidden image embed, Enter should add a new line below the image.
    static func newlineBelowImageEmbed(
        in text: String,
        selectedRange: NSRange,
        vaultURL: URL?
    ) -> (text: String, selectedRange: NSRange)? {
        let ns = text as NSString
        let cursor = min(max(0, selectedRange.location + selectedRange.length), ns.length)
        guard cursor <= ns.length else { return nil }

        for embed in NoteCardEmbedSupport.imageEmbedRanges(in: text, vaultURL: vaultURL) {
            guard embed.location >= cursor else { continue }
            let gap = NSRange(location: cursor, length: embed.location - cursor)
            guard gap.length >= 0, isIgnorableGap(ns.substring(with: gap)) else { continue }

            let afterEmbed = embed.location + embed.length
            if afterEmbed < ns.length, ns.substring(with: NSRange(location: afterEmbed, length: 1)) == "\n" {
                return (text, NSRange(location: afterEmbed + 1, length: 0))
            }
            return MarkdownEditingSupport.insertText("\n", in: text, range: NSRange(location: afterEmbed, length: 0))
        }
        return nil
    }

    /// Arrow-down should skip hidden image embed tokens and land on the first line below.
    static func moveDownPastImageEmbed(
        in text: String,
        selectedRange: NSRange,
        vaultURL: URL?
    ) -> NSRange? {
        let ns = text as NSString
        let cursor = min(max(0, selectedRange.location + selectedRange.length), ns.length)

        for embed in NoteCardEmbedSupport.imageEmbedRanges(in: text, vaultURL: vaultURL) {
            guard cursor <= embed.location else { continue }
            let gap = NSRange(location: cursor, length: embed.location - cursor)
            guard gap.length >= 0, isIgnorableGap(ns.substring(with: gap)) else { continue }

            let afterEmbed = embed.location + embed.length
            if afterEmbed < ns.length, ns.substring(with: NSRange(location: afterEmbed, length: 1)) == "\n" {
                return NSRange(location: afterEmbed + 1, length: 0)
            }
            return NSRange(location: afterEmbed, length: 0)
        }
        return nil
    }

    private static func isIgnorableGap(_ gap: String) -> Bool {
        gap.allSatisfy { $0.isWhitespace }
    }

    /// Wraps a freshly inserted image embed with newlines so the caret can sit on lines above and below.
    static func normalizedAttachmentSnippet(_ snippet: String, in text: String, range: NSRange) -> String {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("![["), trimmed.hasSuffix("]]") else { return snippet }

        let ns = text as NSString
        var normalized = trimmed
        if range.location > 0 {
            let previous = ns.substring(with: NSRange(location: range.location - 1, length: 1))
            if previous != "\n" {
                normalized = "\n" + normalized
            }
        }
        if range.location < ns.length {
            let next = ns.substring(with: NSRange(location: range.location, length: 1))
            if next != "\n" {
                normalized += "\n"
            }
        } else if !normalized.hasSuffix("\n") {
            normalized += "\n"
        }
        return normalized
    }

    /// Keeps exactly one newline after each image embed and removes blank spacer lines.
    static func sanitizeEmbedSpacing(in text: String, vaultURL: URL?) -> String {
        sanitizeEmbedSpacing(in: text, vaultURL: vaultURL, selectedRange: nil).text
    }

    static func sanitizeEmbedSpacing(
        in text: String,
        vaultURL: URL?,
        selectedRange: NSRange?
    ) -> (text: String, selectedRange: NSRange?) {
        let embeds = NoteCardEmbedSupport.imageEmbedRanges(in: text, vaultURL: vaultURL)
        guard !embeds.isEmpty else { return (text, selectedRange) }

        var mutable = text
        var cursor = selectedRange
        var cursorLocation = selectedRange.map { $0.location + $0.length } ?? 0

        for embed in embeds.reversed() {
            let after = embed.location + embed.length
            let ns = mutable as NSString
            guard after <= ns.length else { continue }

            var newlineEnd = after
            while newlineEnd < ns.length,
                  ns.substring(with: NSRange(location: newlineEnd, length: 1)) == "\n" {
                newlineEnd += 1
            }

            if newlineEnd > after + 1 {
                let removed = newlineEnd - after - 1
                let extraStart = mutable.index(mutable.startIndex, offsetBy: after + 1)
                let extraEnd = mutable.index(mutable.startIndex, offsetBy: newlineEnd)
                mutable.removeSubrange(extraStart..<extraEnd)
                if cursorLocation > after + 1 {
                    cursorLocation = max(after + 1, cursorLocation - removed)
                }
            } else if newlineEnd == after {
                let index = mutable.index(mutable.startIndex, offsetBy: after)
                mutable.insert("\n", at: index)
                if cursorLocation >= after {
                    cursorLocation += 1
                }
            }
        }

        while mutable.hasSuffix("\n\n") {
            mutable.removeLast()
            if cursorLocation > mutable.count {
                cursorLocation = mutable.count
            } else if cursorLocation == mutable.count + 1 {
                cursorLocation = mutable.count
            }
        }

        if let selectedRange {
            let length = (mutable as NSString).length
            let location = min(max(0, cursorLocation), length)
            cursor = NSRange(location: location, length: 0)
            _ = selectedRange
        }
        return (mutable, cursor)
    }

    /// @deprecated alias — use sanitizeEmbedSpacing
    static func ensuringEditableTail(in text: String, vaultURL: URL?) -> String {
        sanitizeEmbedSpacing(in: text, vaultURL: vaultURL)
    }

    /// Places the caret on the first line below the last image embed.
    static func caretBelowLastImageEmbed(in text: String, vaultURL: URL?) -> NSRange? {
        guard let last = NoteCardEmbedSupport.imageEmbedRanges(in: text, vaultURL: vaultURL).last else { return nil }
        let after = last.location + last.length
        let ns = text as NSString
        if after < ns.length, ns.substring(with: NSRange(location: after, length: 1)) == "\n" {
            return NSRange(location: after + 1, length: 0)
        }
        return NSRange(location: after, length: 0)
    }
}
