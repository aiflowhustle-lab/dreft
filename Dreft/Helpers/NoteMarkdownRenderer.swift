import Foundation
import SwiftUI

enum NoteMarkdownRenderer {
    private static let wikilinkPattern = #"\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#

    static func wikilinkURL(for target: String) -> URL? {
        var components = URLComponents()
        components.scheme = "dreft"
        components.host = "wikilink"
        components.queryItems = [URLQueryItem(name: "target", value: target)]
        return components.url
    }

    static func wikilinkTarget(from url: URL) -> String? {
        guard url.scheme == "dreft", url.host == "wikilink" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "target" })?
            .value
    }

    /// Converts Obsidian-style wikilinks into markdown links the preview can render.
    static func markdownSource(from content: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: wikilinkPattern) else { return content }

        let nsContent = content as NSString
        var output = content
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length)).reversed()

        for match in matches {
            guard match.numberOfRanges > 1,
                  match.range(at: 1).location != NSNotFound else { continue }

            let target = nsContent.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty, let url = wikilinkURL(for: target) else { continue }

            let display: String
            if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                let alias = nsContent.substring(with: match.range(at: 2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                display = alias.isEmpty ? target : alias
            } else {
                display = target
            }

            let escapedDisplay = display
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            let link = "[\(escapedDisplay)](\(url.absoluteString))"

            guard let range = Range(match.range, in: output) else { continue }
            output.replaceSubrange(range, with: link)
        }

        return output
    }

    static func attributedString(from content: String) -> AttributedString {
        let source = markdownSource(from: content)
        var options = AttributedString.MarkdownParsingOptions()
        options.allowsExtendedAttributes = true
        options.interpretedSyntax = .full
        if let attributed = try? AttributedString(markdown: source, options: options) {
            return attributed
        }
        return AttributedString(source)
    }

    static func previewAttributedString(from content: String) -> AttributedString {
        var attributed = WikilinkEditorSupport.previewAttributedString(from: content)
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = AppColors.noteLink
        }
        return attributed
    }

    static func linkedPreviewAttributedString(from content: String) -> AttributedString {
        let ns = linkedAttributedString(for: content)
        return AttributedString(ns)
    }

    private static func linkedAttributedString(for content: String) -> NSAttributedString {
        let base = WikilinkEditorSupport.attributedString(for: content, selectedRange: NSRange(location: NSNotFound, length: 0))
        let mutable = NSMutableAttributedString(attributedString: base)
        let string = mutable.string as NSString
        var index = 0
        while index < string.length {
            let tail = NSRange(location: index, length: string.length - index)
            let open = string.range(of: "[[", options: [], range: tail)
            guard open.location != NSNotFound else { break }
            let afterOpen = NSRange(location: open.location + 2, length: string.length - open.location - 2)
            let close = string.range(of: "]]", options: [], range: afterOpen)
            guard close.location != NSNotFound else { break }
            let inner = NSRange(location: open.location + 2, length: close.location - open.location - 2)
            if inner.length > 0 {
                let target = string.substring(with: inner)
                    .components(separatedBy: "|").first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !target.isEmpty, let url = wikilinkURL(for: target) {
                    mutable.addAttribute(.link, value: url, range: inner)
                }
            }
            index = close.location + 2
        }
        return mutable
    }
}
