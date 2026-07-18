import Foundation

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
    case externalLink

    case codeBlock
    case horizontalRule
    case callout

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
        case .taskList: return "Task list"
        case .wikilink: return "Add link"
        case .externalLink: return "Add external link"
        case .codeBlock: return "Code block"
        case .horizontalRule: return "Horizontal rule"
        case .callout: return "Callout"
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
            return toggleWrap(open: "**", close: "**", in: text, range: selectedRange)
        case .italic:
            return toggleWrap(open: "*", close: "*", in: text, range: selectedRange)
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
        case .taskList: return toggleLinePrefix("- [ ] ", in: text, range: selectedRange)
        case .wikilink: return insertWikilink(in: text, range: selectedRange)
        case .externalLink: return insertExternalLink(in: text, range: selectedRange)
        case .codeBlock: return insertCodeBlock(in: text, range: selectedRange)
        case .horizontalRule: return insertHorizontalRule(in: text, range: selectedRange)
        case .callout: return insertCallout(in: text, range: selectedRange)
        }
    }

    private static func toggleWrap(
        open: String,
        close: String,
        in text: String,
        range: NSRange
    ) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let clamped = clamp(range, in: ns.length)

        if clamped.length > 0 {
            let selected = ns.substring(with: clamped)
            if selected.hasPrefix(open), selected.hasSuffix(close) {
                let inner = String(selected.dropFirst(open.count).dropLast(close.count))
                return replace(clamped, with: inner, in: text, selectLength: (inner as NSString).length)
            }
            let wrapped = open + selected + close
            return replace(clamped, with: wrapped, in: text, selectLength: (wrapped as NSString).length)
        }

        let beforeStart = max(0, clamped.location - open.count)
        let beforeRange = NSRange(location: beforeStart, length: clamped.location - beforeStart)
        let afterEnd = min(ns.length, clamped.location + close.count)
        let afterRange = NSRange(location: clamped.location, length: afterEnd - clamped.location)

        if beforeRange.length == open.count,
           afterRange.length == close.count,
           ns.substring(with: beforeRange) == open,
           ns.substring(with: afterRange) == close {
            let removeRange = NSRange(location: beforeStart, length: open.count + close.count)
            let newText = ns.replacingCharacters(in: removeRange, with: "")
            return (newText, NSRange(location: beforeStart, length: 0))
        }

        let insertion = open + close
        let newText = ns.replacingCharacters(in: clamped, with: insertion)
        return (newText, NSRange(location: clamped.location + (open as NSString).length, length: 0))
    }

    private static func clearFormatting(in text: String, range: NSRange) -> (text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: clamp(range, in: ns.length))
        let block = ns.substring(with: lineRange)
        var cleaned = block
        let wrappers = ["**", "~~", "==", "*", "`"]
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
