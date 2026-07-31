import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum MarkdownEditAction: String, CaseIterable {
    case bold
    case italic
    case strikethrough
    case highlight
    case inlineCode
    case clearFormatting

    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6
    case body
    case quote

    case bulletList
    case numberedList
    case taskList

    case wikilink
    case embed
    case attachment
    case externalLink

    case codeBlock
    case horizontalRule
    case callout

    case indent
    case outdent
    case tag

    var menuTitle: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .strikethrough: return "Strikethrough"
        case .highlight: return "Highlight"
        case .inlineCode: return "Code"
        case .clearFormatting: return "Clear formatting"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .heading4: return "Heading 4"
        case .heading5: return "Heading 5"
        case .heading6: return "Heading 6"
        case .body: return "Body"
        case .quote: return "Quote"
        case .bulletList: return "Bullet list"
        case .numberedList: return "Numbered list"
        case .taskList: return "Checkbox"
        case .wikilink: return "Add link"
        case .embed: return "Add embed"
        case .attachment: return "Insert attachment"
        case .externalLink: return "Add external link"
        case .codeBlock: return "Code block"
        case .horizontalRule: return "Horizontal rule"
        case .callout: return "Callout"
        case .indent: return "Indent"
        case .outdent: return "Outdent"
        case .tag: return "Tag"
        }
    }
}

enum MarkdownEditingSupport {
    static func apply(
        _ action: MarkdownEditAction,
        text: String,
        selectedRange: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        switch action {
        case .bold:
            return toggleBold(in: text, range: selectedRange)
        case .italic:
            return toggleItalic(in: text, range: selectedRange)
        case .strikethrough:
            return toggleWrap(open: "~~", close: "~~", in: text, range: selectedRange)
        case .highlight:
            return toggleWrap(open: "==", close: "==", in: text, range: selectedRange)
        case .inlineCode:
            return toggleWrap(open: "`", close: "`", in: text, range: selectedRange)
        case .clearFormatting:
            return clearFormatting(in: text, range: selectedRange)
        case .heading1: return setHeading(level: 1, in: text, range: selectedRange)
        case .heading2: return setHeading(level: 2, in: text, range: selectedRange)
        case .heading3: return setHeading(level: 3, in: text, range: selectedRange)
        case .heading4: return setHeading(level: 4, in: text, range: selectedRange)
        case .heading5: return setHeading(level: 5, in: text, range: selectedRange)
        case .heading6: return setHeading(level: 6, in: text, range: selectedRange)
        case .body: return setHeading(level: 0, in: text, range: selectedRange)
        case .quote: return toggleLinePrefix("> ", in: text, range: selectedRange)
        case .bulletList: return toggleLinePrefix("- ", in: text, range: selectedRange)
        case .numberedList: return toggleNumberedList(in: text, range: selectedRange)
        case .taskList: return applyToggleTaskList(in: text, range: selectedRange)
        case .wikilink: return insertWikilink(in: text, range: selectedRange)
        case .embed: return insertEmbed(in: text, range: selectedRange)
        case .attachment: return insertEmbed(in: text, range: selectedRange)
        case .externalLink: return insertExternalLink(in: text, range: selectedRange)
        case .codeBlock: return insertCodeBlock(in: text, range: selectedRange)
        case .horizontalRule: return insertHorizontalRule(in: text, range: selectedRange)
        case .callout: return insertCallout(in: text, range: selectedRange)
        case .indent: return adjustIndent(in: text, range: selectedRange, delta: 2)
        case .outdent: return adjustIndent(in: text, range: selectedRange, delta: -2)
        case .tag: return insertPlainText("#", in: text, range: selectedRange)
        }
    }

    static func toggleTaskList(
        in text: String,
        selectedRange: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        applyToggleTaskList(in: text, range: selectedRange)
    }

    static func insertText(
        _ insertion: String,
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        insertPlainText(insertion, in: text, range: range)
    }

    private static let inlineWrapperPairs: [(String, String)] = [
        ("***", "***"), ("**", "**"), ("~~", "~~"), ("==", "=="), ("*", "*"), ("`", "`"),
    ]

    private static func toggleWrap(
        open: String,
        close: String,
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)
        let effectiveRange = clamped.length > 0
            ? expandInlineSelection(in: text, range: clamped)
            : clamped

        if effectiveRange.length > 0 {
            let selected = ns.substring(with: effectiveRange)
            if selected.hasPrefix(open), selected.hasSuffix(close) {
                let inner = String(selected.dropFirst(open.count).dropLast(close.count))
                return replace(effectiveRange, with: inner, in: text, selectLength: (inner as NSString).length)
            }
            let wrapped = open + selected + close
            return replace(effectiveRange, with: wrapped, in: text, selectLength: (wrapped as NSString).length)
        }

        let beforeStart = max(0, effectiveRange.location - open.count)
        let beforeRange = NSRange(location: beforeStart, length: effectiveRange.location - beforeStart)
        let afterEnd = min(ns.length, effectiveRange.location + close.count)
        let afterRange = NSRange(location: effectiveRange.location, length: afterEnd - effectiveRange.location)

        if beforeRange.length == open.count,
           afterRange.length == close.count,
           ns.substring(with: beforeRange) == open,
           ns.substring(with: afterRange) == close {
            let removeRange = NSRange(location: beforeStart, length: open.count + close.count)
            let newText = ns.replacingCharacters(in: removeRange, with: "")
            return (newText, NSRange(location: beforeStart, length: 0))
        }

        let insertion = open + close
        let newText = ns.replacingCharacters(in: effectiveRange, with: insertion)
        return (newText, NSRange(location: effectiveRange.location + (open as NSString).length, length: 0))
    }

    private static func toggleBold(
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = expandInlineSelection(in: text, range: range)

        if clamped.length > 0 {
            let selected = ns.substring(with: clamped)
            if selected.hasPrefix("***"), selected.hasSuffix("***"), selected.count >= 6 {
                let inner = String(selected.dropFirst(3).dropLast(3))
                let result = "*" + inner + "*"
                return replace(clamped, with: result, in: text, selectLength: (result as NSString).length)
            }
            if selected.hasPrefix("**"), selected.hasSuffix("**"), selected.count >= 4 {
                let inner = String(selected.dropFirst(2).dropLast(2))
                return replace(clamped, with: inner, in: text, selectLength: (inner as NSString).length)
            }
            if selected.hasPrefix("*"), selected.hasSuffix("*"),
               !selected.hasPrefix("**"), selected.count >= 2 {
                let inner = String(selected.dropFirst(1).dropLast(1))
                let result = "***" + inner + "***"
                return replace(clamped, with: result, in: text, selectLength: (result as NSString).length)
            }
            return toggleWrap(open: "**", close: "**", in: text, range: clamped)
        }

        return toggleWrap(open: "**", close: "**", in: text, range: clamped)
    }

    private static func toggleItalic(
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = expandInlineSelection(in: text, range: range)

        if clamped.length > 0 {
            let selected = ns.substring(with: clamped)
            if selected.hasPrefix("***"), selected.hasSuffix("***"), selected.count >= 6 {
                let inner = String(selected.dropFirst(3).dropLast(3))
                let result = "**" + inner + "**"
                return replace(clamped, with: result, in: text, selectLength: (result as NSString).length)
            }
            if selected.hasPrefix("**"), selected.hasSuffix("**"), selected.count >= 4 {
                let inner = String(selected.dropFirst(2).dropLast(2))
                let result = "***" + inner + "***"
                return replace(clamped, with: result, in: text, selectLength: (result as NSString).length)
            }
            if selected.hasPrefix("*"), selected.hasSuffix("*"),
               !selected.hasPrefix("**"), selected.count >= 2 {
                let inner = String(selected.dropFirst(1).dropLast(1))
                return replace(clamped, with: inner, in: text, selectLength: (inner as NSString).length)
            }
            return toggleWrap(open: "*", close: "*", in: text, range: clamped)
        }

        return toggleWrap(open: "*", close: "*", in: text, range: clamped)
    }

    private static func clearFormatting(in text: String, range: NSRange) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: clamp(range, in: ns.length))
        let block = ns.substring(with: lineRange)
        var cleaned = block
        let wrappers = ["***", "**", "~~", "==", "*", "`"]
        for wrapper in wrappers {
            cleaned = cleaned.replacingOccurrences(of: wrapper, with: "")
        }
        cleaned = cleaned.replacingOccurrences(
            of: #"^\s{0,3}#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"^\s*[-*+]\s+"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"^\s*\d+\.\s+"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"^\s*>\s?"#,
            with: "",
            options: .regularExpression
        )
        return replace(lineRange, with: cleaned, in: text, selectLength: (cleaned as NSString).length)
    }

    private static func setHeading(
        level: Int,
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: clamp(range, in: ns.length))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }

        line = line.replacingOccurrences(
            of: #"^\s{0,3}#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"^\s*>\s?"#,
            with: "",
            options: .regularExpression
        )

        let prefix = level > 0 ? String(repeating: "#", count: level) + " " : ""
        let updated = prefix + line + (lineRange.length > 0 && ns.substring(with: lineRange).hasSuffix("\n") ? "\n" : "")
        return replace(lineRange, with: updated, in: text, selectLength: (line.trimmingCharacters(in: .newlines) as NSString).length)
    }

    private static func applyToggleTaskList(
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: clamp(range, in: ns.length))
        var line = ns.substring(with: lineRange)
        let hadNewline = line.hasSuffix("\n")
        if hadNewline { line.removeLast() }

        let taskPattern = #"^(\s*[-*+]\s+\[)([ xX])(\]\s*)(.*)$"#
        if let regex = try? NSRegularExpression(pattern: taskPattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
           match.numberOfRanges >= 5 {
            let nsLine = line as NSString
            let mark = nsLine.substring(with: match.range(at: 2))
            let nextMark = mark.lowercased() == "x" ? " " : "x"
            let prefix = nsLine.substring(with: match.range(at: 1))
            let suffix = nsLine.substring(with: match.range(at: 3))
            let bodyRange = match.range(at: 4)
            let body = bodyRange.location != NSNotFound ? nsLine.substring(with: bodyRange) : ""
            line = prefix + nextMark + suffix + body
        } else if line.range(of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#, options: .regularExpression) != nil {
            line = line.replacingOccurrences(
                of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#,
                with: "",
                options: .regularExpression
            )
        } else {
            line = "- [ ] " + line
        }

        if hadNewline { line += "\n" }
        return replace(lineRange, with: line, in: text, selectLength: max(0, (line as NSString).length - (hadNewline ? 1 : 0)))
    }

    /// Enter on a task line continues with another checkbox; Enter on an empty task line exits to normal text.
    static func newlineInTaskList(
        in text: String,
        selectedRange: NSRange
    ) -> (text: String, selectedRange: NSRange)? {
        let ns = text as NSString
        let clamped = clamp(selectedRange, in: ns.length)
        let lineRange = ns.lineRange(for: clamped)
        var line = ns.substring(with: lineRange)
        let hadNewline = line.hasSuffix("\n")
        if hadNewline { line.removeLast() }

        let taskPattern = #"^(\s*[-*+]\s+\[)([ xX])(\]\s*)(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: taskPattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
              match.numberOfRanges >= 5 else { return nil }

        let bodyRange = match.range(at: 4)
        let body = bodyRange.location != NSNotFound
            ? (line as NSString).substring(with: bodyRange)
            : ""

        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return replace(lineRange, with: "\n", in: text, selectLength: 0)
        }

        return insertPlainText("\n- [ ] ", in: text, range: clamped)
    }

    private struct InlineWrapperSpan {
        let openRange: NSRange
        let closeRange: NSRange
        let open: String
        let close: String

        var innerRange: NSRange {
            NSRange(
                location: openRange.location + openRange.length,
                length: max(0, closeRange.location - openRange.location - openRange.length)
            )
        }
    }

    /// Handles Enter for task lists and inline markdown (bold, highlight, etc.).
    /// Inserts through styled content so hidden delimiters stay hidden like canvas note cards.
    static func newlineInDocument(
        in text: String,
        selectedRange: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        if let task = newlineInTaskList(in: text, selectedRange: selectedRange) {
            return task
        }

        let ns = text as NSString
        let clamped = clamp(selectedRange, in: ns.length)
        let caret = clamped.location + clamped.length

        if let span = innermostInlineWrapper(in: text, at: caret) {
            let inner = span.innerRange
            let open = span.open
            let close = span.close

            if caret >= inner.location && caret <= NSMaxRange(inner) {
                if caret == NSMaxRange(inner) {
                    let insertAt = span.closeRange.location + span.closeRange.length
                    return insertPlainText("\n", in: text, range: NSRange(location: insertAt, length: 0))
                }

                let innerText = ns.substring(with: inner)
                let split = caret - inner.location
                let before = (innerText as NSString).substring(to: split)
                let after = (innerText as NSString).substring(from: split)
                let replacement = open + before + close + "\n" + after
                let fullRange = NSRange(
                    location: span.openRange.location,
                    length: NSMaxRange(span.closeRange) - span.openRange.location
                )
                let newText = ns.replacingCharacters(in: fullRange, with: replacement)
                let newCaret = span.openRange.location + (open as NSString).length + (before as NSString).length + (close as NSString).length + 1
                return (newText, NSRange(location: newCaret, length: 0))
            }

            if caret > NSMaxRange(inner) && caret <= NSMaxRange(span.closeRange) {
                let insertAt = span.closeRange.location + span.closeRange.length
                return insertPlainText("\n", in: text, range: NSRange(location: insertAt, length: 0))
            }
        }

        return insertPlainText("\n", in: text, range: clamped)
    }

    private static func innermostInlineWrapper(in text: String, at caret: Int) -> InlineWrapperSpan? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }

        let clampedCaret = min(max(caret, 0), ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: clampedCaret, length: 0))
        let lineEnd = lineRange.location + lineRange.length

        var best: InlineWrapperSpan?
        var bestSize = Int.max

        for (open, close) in inlineWrapperPairs {
            var searchStart = lineRange.location

            while searchStart < lineEnd {
                let tail = NSRange(location: searchStart, length: lineEnd - searchStart)
                let openRange = ns.range(of: open, options: [], range: tail)
                guard openRange.location != NSNotFound else { break }

                let afterOpen = openRange.location + openRange.length
                let closeSearch = NSRange(location: afterOpen, length: lineEnd - afterOpen)
                let closeRange = ns.range(of: close, options: [], range: closeSearch)
                guard closeRange.location != NSNotFound else {
                    searchStart = openRange.location + 1
                    continue
                }

                let spanStart = openRange.location
                let spanEnd = closeRange.location + closeRange.length
                if clampedCaret >= spanStart && clampedCaret <= spanEnd {
                    let size = spanEnd - spanStart
                    if size < bestSize {
                        bestSize = size
                        best = InlineWrapperSpan(
                            openRange: openRange,
                            closeRange: closeRange,
                            open: open,
                            close: close
                        )
                    }
                }
                searchStart = openRange.location + 1
            }
        }

        return best
    }

    private static func toggleLinePrefix(
        _ prefix: String,
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: clamp(range, in: ns.length))
        var line = ns.substring(with: lineRange)
        let hadNewline = line.hasSuffix("\n")
        if hadNewline { line.removeLast() }

        if line.hasPrefix(prefix) {
            line = String(line.dropFirst(prefix.count))
        } else {
            line = prefix + line
        }
        if hadNewline { line += "\n" }
        return replace(lineRange, with: line, in: text, selectLength: max(0, (line as NSString).length - (hadNewline ? 1 : 0)))
    }

    private static func toggleNumberedList(
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: clamp(range, in: ns.length))
        var line = ns.substring(with: lineRange)
        let hadNewline = line.hasSuffix("\n")
        if hadNewline { line.removeLast() }

        if let match = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            line.replaceSubrange(match, with: "")
        } else {
            line = "1. " + line
        }
        if hadNewline { line += "\n" }
        return replace(lineRange, with: line, in: text, selectLength: max(0, (line as NSString).length - (hadNewline ? 1 : 0)))
    }

    private static func insertWikilink(
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)
        if clamped.length > 0 {
            let selected = ns.substring(with: clamped)
            let link = "[[\(selected)]]"
            return replace(clamped, with: link, in: text, selectLength: (link as NSString).length)
        }
        let link = "[[]]"
        let newText = ns.replacingCharacters(in: clamped, with: link)
        return (newText, NSRange(location: clamped.location + 2, length: 0))
    }

    private static func insertEmbed(
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)
        if clamped.length > 0 {
            let selected = ns.substring(with: clamped)
            let embed = "![[\(selected)]]"
            return replace(clamped, with: embed, in: text, selectLength: (embed as NSString).length)
        }
        let embed = "![[]]"
        let newText = ns.replacingCharacters(in: clamped, with: embed)
        return (newText, NSRange(location: clamped.location + 3, length: 0))
    }

    private static func insertExternalLink(
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)
        let label = clamped.length > 0 ? ns.substring(with: clamped) : "link"
        let link = "[\(label)](https://)"
        let newText = ns.replacingCharacters(in: clamped, with: link)
        let urlStart = clamped.location + (label as NSString).length + 3
        let urlLength = "https://".count
        return (newText, NSRange(location: urlStart, length: urlLength))
    }

    private static func insertCodeBlock(
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)
        let selected = clamped.length > 0 ? ns.substring(with: clamped) : ""
        let block = "\n```\n\(selected)\n```\n"
        let newText = ns.replacingCharacters(in: clamped, with: block)
        if selected.isEmpty {
            return (newText, NSRange(location: clamped.location + 5, length: 0))
        }
        return (newText, NSRange(location: clamped.location, length: (block as NSString).length))
    }

    private static func insertHorizontalRule(
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)
        let rule = "\n\n---\n\n"
        let newText = ns.replacingCharacters(in: clamped, with: rule)
        return (newText, NSRange(location: clamped.location + (rule as NSString).length, length: 0))
    }

    private static func insertCallout(
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)
        let callout = "\n> [!note]\n> \n"
        let newText = ns.replacingCharacters(in: clamped, with: callout)
        return (newText, NSRange(location: clamped.location + callout.count - 1, length: 0))
    }

    private static func insertPlainText(
        _ insertion: String,
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)
        let newText = ns.replacingCharacters(in: clamped, with: insertion)
        return (newText, NSRange(location: clamped.location + insertion.count, length: 0))
    }

    private static func adjustIndent(
        in text: String,
        range: NSRange,
        delta: Int
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)
        let blockRange = ns.lineRange(for: clamped)
        let block = ns.substring(with: blockRange)
        let lines = block.components(separatedBy: "\n")
        let adjusted = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            if delta > 0 {
                return String(repeating: " ", count: delta) + line
            }
            var remaining = -delta
            var result = line
            while remaining > 0, result.hasPrefix(" ") {
                result.removeFirst()
                remaining -= 1
            }
            while remaining > 0, result.hasPrefix("\t") {
                result.removeFirst()
                remaining -= 1
            }
            return result
        }
        let updated = adjusted.joined(separator: "\n")
        return replace(blockRange, with: updated, in: text, selectLength: clamped.length)
    }

    /// If the selection covers only inner text, include surrounding inline markdown markers.
    private static func expandInlineSelection(in text: String, range: NSRange) -> NSRange {
        let ns = text as NSString
        var expanded = clamp(range, in: ns.length)
        guard expanded.length > 0 else { return expanded }

        var changed = true
        while changed {
            changed = false
            for (open, close) in inlineWrapperPairs {
                let openLength = (open as NSString).length
                let closeLength = (close as NSString).length
                let beforeStart = expanded.location - openLength
                let afterStart = expanded.location + expanded.length
                guard beforeStart >= 0, afterStart + closeLength <= ns.length else { continue }

                let before = ns.substring(with: NSRange(location: beforeStart, length: openLength))
                let after = ns.substring(with: NSRange(location: afterStart, length: closeLength))
                if before == open, after == close {
                    expanded = NSRange(
                        location: beforeStart,
                        length: openLength + expanded.length + closeLength
                    )
                    changed = true
                }
            }
        }

        return expanded
    }

    private static func replace(
        _ range: NSRange,
        with replacement: String,
        in text: String,
        selectLength: Int
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let newText = ns.replacingCharacters(in: range, with: replacement)
        return (newText, NSRange(location: range.location, length: selectLength))
    }

    private static func clamp(_ range: NSRange, in length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let upper = min(range.location + range.length, length)
        return NSRange(location: location, length: max(0, upper - location))
    }
}

/// Obsidian-style live preview editing: markdown (`**bold**`) lives in bindings;
/// the text view shows styled text without syntax markers.
enum MarkdownWysiwygEditingSupport {
    struct IndexMap {
        let markdownLength: Int
        let displayLength: Int
        /// Maps each display character index to its markdown start index.
        let displayToMarkdown: [Int]

        func displayRange(fromMarkdown range: NSRange) -> NSRange {
            guard range.location != NSNotFound, markdownLength > 0 else {
                return NSRange(location: 0, length: 0)
            }
            let mdStart = clamp(range.location, upper: markdownLength)
            let mdEnd = clamp(range.location + range.length, upper: markdownLength)

            let displayStart = displayIndex(forMarkdownIndex: mdStart)
            let displayEnd = displayIndex(forMarkdownIndex: mdEnd)
            return NSRange(location: displayStart, length: max(0, displayEnd - displayStart))
        }

        func markdownRange(fromDisplay range: NSRange) -> NSRange {
            guard range.location != NSNotFound else { return NSRange(location: 0, length: 0) }
            let displayStart = clamp(range.location, upper: displayLength)
            let displayEnd = clamp(range.location + range.length, upper: displayLength)

            let markdownStart = displayStart < displayToMarkdown.count
                ? displayToMarkdown[displayStart]
                : markdownLength
            let markdownEnd = displayEnd < displayToMarkdown.count
                ? displayToMarkdown[displayEnd]
                : markdownLength
            return NSRange(location: markdownStart, length: max(0, markdownEnd - markdownStart))
        }

        private func displayIndex(forMarkdownIndex markdownIndex: Int) -> Int {
            if markdownIndex >= markdownLength {
                return displayLength
            }
            guard !displayToMarkdown.isEmpty else { return 0 }
            for (displayIndex, mappedMarkdownIndex) in displayToMarkdown.enumerated() {
                if mappedMarkdownIndex >= markdownIndex {
                    return displayIndex
                }
            }
            return displayLength
        }

        private func clamp(_ value: Int, upper: Int) -> Int {
            min(max(value, 0), upper)
        }
    }

    static func indexMap(
        for markdown: String,
        fontSize: CGFloat,
        editorBackground: Color,
        hideTaskListMarkers: Bool
    ) -> IndexMap {
        let displaySource = displaySourceString(from: markdown, hideTaskListMarkers: hideTaskListMarkers)
        let sourceToMarkdown = sourceToMarkdownIndices(
            markdown: markdown,
            displaySource: displaySource,
            hideTaskListMarkers: hideTaskListMarkers
        )

        let styledForMapping = WikilinkEditorSupport.attributedString(
            for: displaySource,
            selectedRange: NSRange(location: NSNotFound, length: 0),
            fontSize: fontSize,
            hiddenDelimiterOn: editorBackground,
            hideTaskListMarkers: false
        )

        var displayToMarkdown: [Int] = []
        displayToMarkdown.reserveCapacity(styledForMapping.length)
        var displaySourceIndex = 0

        for styledIndex in 0..<styledForMapping.length {
            if isHiddenDelimiter(in: styledForMapping, at: styledIndex) {
                displaySourceIndex += 1
                continue
            }
            if displaySourceIndex < sourceToMarkdown.count {
                displayToMarkdown.append(sourceToMarkdown[displaySourceIndex])
            } else {
                displayToMarkdown.append(markdown.utf16.count)
            }
            displaySourceIndex += 1
        }

        return IndexMap(
            markdownLength: markdown.utf16.count,
            displayLength: displayToMarkdown.count,
            displayToMarkdown: displayToMarkdown
        )
    }

    /// Markdown with task prefixes removed — only the visible body text remains per task line.
    static func displaySourceString(from markdown: String, hideTaskListMarkers: Bool) -> String {
        guard hideTaskListMarkers else { return markdown }

        let parts = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        let lines = parts.map { part -> String in
            let line = String(part)
            if let body = NoteCardTaskSupport.taskBodyMarkdown(in: line) {
                // Keep empty task rows in the layout so checkbox overlays stay aligned while typing.
                return body.isEmpty ? "\u{200B}" : body
            }
            return line
        }
        return lines.joined(separator: "\n")
    }

    static func displayLineStartIndex(
        forMarkdownLineStart lineStart: Int,
        markdown: String,
        displaySource: String
    ) -> Int {
        let parts = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var markdownOffset = 0
        var displayOffset = 0

        for part in parts {
            if markdownOffset == lineStart {
                return displayOffset
            }
            let line = String(part)
            let displayLine = NoteCardTaskSupport.taskBodyMarkdown(in: line) ?? line
            displayOffset += (displayLine as NSString).length + 1
            markdownOffset += (line as NSString).length + 1
        }
        return displayOffset
    }

    static func displayAttributedString(
        from markdown: String,
        fontSize: CGFloat,
        editorBackground: Color,
        hideTaskListMarkers: Bool
    ) -> NSAttributedString {
        let displaySource = displaySourceString(from: markdown, hideTaskListMarkers: hideTaskListMarkers)
        let styled = styledDisplayString(
            from: displaySource,
            fontSize: fontSize,
            editorBackground: editorBackground
        )
        guard hideTaskListMarkers else { return styled }
        let indented = applyTaskLineIndents(
            to: styled,
            originalMarkdown: markdown,
            fontSize: fontSize
        )
        return applyCheckedTaskStyling(to: indented, originalMarkdown: markdown)
    }

    private static func styledDisplayString(
        from displaySource: String,
        fontSize: CGFloat,
        editorBackground: Color
    ) -> NSAttributedString {
        WikilinkEditorSupport.displayAttributedString(
            from: displaySource,
            selectedRange: NSRange(location: NSNotFound, length: 0),
            fontSize: fontSize,
            hiddenDelimiterOn: editorBackground,
            hideTaskListMarkers: false
        )
    }

    private static func sourceToMarkdownIndices(
        markdown: String,
        displaySource: String,
        hideTaskListMarkers: Bool
    ) -> [Int] {
        guard hideTaskListMarkers else {
            return Array(0..<(markdown as NSString).length)
        }

        let mdParts = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        let displayParts = displaySource.split(separator: "\n", omittingEmptySubsequences: false)
        var map: [Int] = []
        map.reserveCapacity((displaySource as NSString).length)

        for index in 0..<mdParts.count {
            let mdLine = String(mdParts[index])
            let displayLine = index < displayParts.count ? String(displayParts[index]) : ""
            let mdLineStart = mdParts.prefix(index).reduce(0) { partial, part in
                partial + (String(part) as NSString).length + 1
            }
            let displayNSString = displayLine as NSString

            if NoteCardTaskSupport.taskBodyMarkdown(in: mdLine) != nil {
                let prefixLength = (mdLine as NSString).length - displayNSString.length
                let bodyStart = mdLineStart + max(0, prefixLength)
                for charIndex in 0..<displayNSString.length {
                    map.append(bodyStart + charIndex)
                }
            } else {
                for charIndex in 0..<displayNSString.length {
                    map.append(mdLineStart + charIndex)
                }
            }

            if index < mdParts.count - 1 {
                map.append(mdLineStart + (mdLine as NSString).length)
            }
        }

        return map
    }

    private static func applyTaskLineIndents(
        to styled: NSAttributedString,
        originalMarkdown: String,
        fontSize: CGFloat
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: styled)
        guard mutable.length > 0 else { return mutable }

        let indent = NoteCardTaskSupport.lineLeadingInset(fontSize: fontSize)
        let mdParts = originalMarkdown.split(separator: "\n", omittingEmptySubsequences: false)
        let content = mutable.string as NSString

        var lineIndex = 0
        var location = 0
        while location < content.length, lineIndex < mdParts.count {
            let lineRange = content.lineRange(for: NSRange(location: location, length: 0))
            let mdLine = String(mdParts[lineIndex])

            if NoteCardTaskSupport.parseTaskLine(mdLine) != nil,
               let styleRange = contentRangeExcludingTrailingNewline(lineRange, in: content),
               styleRange.length > 0 {
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = indent
                style.headIndent = indent
                mutable.addAttribute(.paragraphStyle, value: style, range: styleRange)
            }

            lineIndex += 1
            location = NSMaxRange(lineRange)
        }

        return mutable
    }

    private static func applyCheckedTaskStyling(
        to styled: NSAttributedString,
        originalMarkdown: String
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: styled)
        guard mutable.length > 0 else { return mutable }

        let mdParts = originalMarkdown.split(separator: "\n", omittingEmptySubsequences: false)
        let content = mutable.string as NSString

        var lineIndex = 0
        var location = 0
        while location < content.length, lineIndex < mdParts.count {
            let lineRange = content.lineRange(for: NSRange(location: location, length: 0))
            let mdLine = String(mdParts[lineIndex])

            if let task = NoteCardTaskSupport.parseTaskLine(mdLine),
               case .task(let checked, _, _) = task,
               checked,
               let styleRange = contentRangeExcludingTrailingNewline(lineRange, in: content),
               styleRange.length > 0 {
                mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: styleRange)
                #if canImport(AppKit)
                mutable.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: styleRange)
                #else
                mutable.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: styleRange)
                #endif
            }

            lineIndex += 1
            location = NSMaxRange(lineRange)
        }

        return mutable
    }

    /// Returns a range clamped to `content` and excluding a trailing line-feed when present.
    private static func contentRangeExcludingTrailingNewline(
        _ lineRange: NSRange,
        in content: NSString
    ) -> NSRange? {
        guard lineRange.location >= 0,
              lineRange.length >= 0,
              lineRange.location <= content.length else { return nil }

        var range = lineRange
        if range.length > 0,
           range.location + range.length <= content.length,
           content.character(at: range.location + range.length - 1) == 0x0A {
            range.length -= 1
        }

        guard range.length > 0, NSMaxRange(range) <= content.length else { return nil }
        return range
    }

    static func displayRange(
        fromMarkdown range: NSRange,
        in markdown: String,
        fontSize: CGFloat,
        editorBackground: Color,
        hideTaskListMarkers: Bool
    ) -> NSRange {
        indexMap(
            for: markdown,
            fontSize: fontSize,
            editorBackground: editorBackground,
            hideTaskListMarkers: hideTaskListMarkers
        ).displayRange(fromMarkdown: range)
    }

    static func markdownRange(
        fromDisplay range: NSRange,
        in markdown: String,
        fontSize: CGFloat,
        editorBackground: Color,
        hideTaskListMarkers: Bool
    ) -> NSRange {
        indexMap(
            for: markdown,
            fontSize: fontSize,
            editorBackground: editorBackground,
            hideTaskListMarkers: hideTaskListMarkers
        ).markdownRange(fromDisplay: range)
    }

    static func markdown(from display: NSAttributedString) -> String {
        guard display.length > 0 else { return "" }

        var result = ""
        let fullRange = NSRange(location: 0, length: display.length)
        display.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let chunk = (display.string as NSString).substring(with: range)
            result += wrappedMarkdownChunk(chunk, attributes: attributes)
        }
        return result
    }

    private static func wrappedMarkdownChunk(_ chunk: String, attributes: [NSAttributedString.Key: Any]) -> String {
        guard !chunk.isEmpty else { return chunk }

        var text = chunk
        if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 {
            text = "~~\(text)~~"
        }
        if attributes[.backgroundColor] != nil {
            text = "==\(text)=="
        }
        #if canImport(UIKit)
        if let font = attributes[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            let bold = traits.contains(.traitBold)
            let italic = traits.contains(.traitItalic)
            if bold && italic {
                text = "***\(text)***"
            } else if bold {
                text = "**\(text)**"
            } else if italic {
                text = "*\(text)*"
            }
        }
        #elseif canImport(AppKit)
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            let bold = traits.contains(.bold)
            let italic = traits.contains(.italic)
            if bold && italic {
                text = "***\(text)***"
            } else if bold {
                text = "**\(text)**"
            } else if italic {
                text = "*\(text)*"
            }
        }
        #endif
        return text
    }

    private static func isHiddenDelimiter(in attributed: NSAttributedString, at index: Int) -> Bool {
        guard index >= 0, index < attributed.length,
              let font = attributed.attribute(.font, at: index, effectiveRange: nil) else { return false }
        #if canImport(UIKit)
        return (font as? UIFont)?.pointSize ?? 16 <= 0.02
        #else
        return (font as? NSFont)?.pointSize ?? 16 <= 0.02
        #endif
    }
}
