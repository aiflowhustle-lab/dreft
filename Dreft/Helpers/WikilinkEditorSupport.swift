import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct WikilinkActiveQuery: Equatable {
    var query: String
    /// Range from the opening `[[` through the cursor — replaced when picking a suggestion.
    var replaceRange: NSRange
}

enum WikilinkEditorSupport {
    static let bracketColor = AppColors.textMuted
    static let linkColor = AppColors.noteLink
    /// Matches the note editor surface so completed-link brackets disappear.
    static let hiddenBracketColor = AppColors.canvasBackground
    static let bodyFontSize: CGFloat = 16

    /// Label shown in the suggest list (Obsidian-style, includes extensions for canvas/images).
    static func suggestionLabel(for file: WorkspaceFileEntry) -> String {
        switch file.kind {
        case .note:
            return file.name
        case .canvas:
            return "\(file.name).canvas"
        case .image:
            return (file.relativePath as NSString).lastPathComponent
        case .folder:
            return file.name
        }
    }

    /// Target inserted inside `[[...]]`.
    static func insertTarget(for file: WorkspaceFileEntry) -> String {
        suggestionLabel(for: file)
    }

    static func activeQuery(in content: String, cursor: Int) -> WikilinkActiveQuery? {
        let ns = content as NSString
        let clampedCursor = min(max(cursor, 0), ns.length)
        guard clampedCursor >= 2 else { return nil }

        let searchRange = NSRange(location: 0, length: clampedCursor)
        let openRange = ns.range(of: "[[", options: .backwards, range: searchRange)
        guard openRange.location != NSNotFound else { return nil }

        let typedRange = NSRange(
            location: openRange.location + 2,
            length: clampedCursor - openRange.location - 2
        )
        if typedRange.length > 0 {
            let typed = ns.substring(with: typedRange)
            if typed.contains("]]") { return nil }
        }

        let rawQuery = typedRange.length > 0 ? ns.substring(with: typedRange) : ""
        let fileQuery = rawQuery
            .components(separatedBy: "|").first?
            .components(separatedBy: "#").first?
            .components(separatedBy: "^").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return WikilinkActiveQuery(
            query: fileQuery,
            replaceRange: NSRange(location: openRange.location, length: clampedCursor - openRange.location)
        )
    }

    static func insertSuggestion(
        _ target: String,
        into content: String,
        replaceRange: NSRange
    ) -> (text: String, cursor: Int) {
        let ns = content as NSString
        let insertion = "[[\(target)]]"
        let newText = ns.replacingCharacters(in: replaceRange, with: insertion)
        let cursor = replaceRange.location + (insertion as NSString).length
        return (newText, cursor)
    }

    static func previewAttributedString(from content: String) -> AttributedString {
        AttributedString(attributedString(for: content, selectedRange: NSRange(location: NSNotFound, length: 0)))
    }

    static func attributedString(
        for content: String,
        selectedRange: NSRange,
        fontSize: CGFloat = bodyFontSize,
        hiddenDelimiterOn: Color = AppColors.canvasBackground
    ) -> NSAttributedString {
        let storage = NSMutableAttributedString(
            string: content,
            attributes: baseBodyAttributes(fontSize: fontSize)
        )
        restyleInPlace(
            storage,
            selectedRange: selectedRange,
            fontSize: fontSize,
            hiddenDelimiterOn: hiddenDelimiterOn
        )
        return storage
    }

    /// Updates markdown/wikilink attributes without replacing plain text — preserves NSTextView undo.
    static func restyleInPlace(
        _ storage: NSMutableAttributedString,
        selectedRange: NSRange,
        fontSize: CGFloat = bodyFontSize,
        hiddenDelimiterOn: Color = AppColors.canvasBackground
    ) {
        guard storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.setAttributes(baseBodyAttributes(fontSize: fontSize), range: fullRange)
        storage.removeAttribute(.strikethroughStyle, range: fullRange)
        storage.removeAttribute(.backgroundColor, range: fullRange)
        storage.removeAttribute(.underlineStyle, range: fullRange)
        storage.removeAttribute(.underlineColor, range: fullRange)
        applyInlineMarkdownStyling(
            to: storage,
            selectedRange: selectedRange,
            fontSize: fontSize,
            hiddenDelimiterOn: hiddenDelimiterOn
        )
        applyWikilinkStyling(to: storage, selectedRange: selectedRange, hiddenDelimiterOn: hiddenDelimiterOn)
    }

    private static func baseBodyAttributes(fontSize: CGFloat = bodyFontSize) -> [NSAttributedString.Key: Any] {
        #if canImport(AppKit)
        let font = NSFont.systemFont(ofSize: fontSize)
        let color = NSColor(textColorForPlatform)
        #else
        let font = UIFont.systemFont(ofSize: fontSize)
        let color = UIColor(textColorForPlatform)
        #endif
        return [
            .font: font,
            .foregroundColor: color,
        ]
    }

    private static var textColorForPlatform: Color {
        AppColors.textPrimary
    }

    private static func platformColor(_ color: Color) -> Any {
        #if canImport(AppKit)
        return NSColor(color)
        #else
        return UIColor(color)
        #endif
    }

    private static func applyInlineMarkdownStyling(
        to storage: NSMutableAttributedString,
        selectedRange: NSRange,
        fontSize: CGFloat,
        hiddenDelimiterOn: Color
    ) {
        let content = storage.string as NSString
        guard content.length > 0 else { return }

        let highlight = platformColor(Color.yellow.opacity(0.35))

        applyWrappedMarkdown(
            to: storage,
            content: content,
            selectedRange: selectedRange,
            open: "**",
            close: "**",
            hiddenDelimiterOn: hiddenDelimiterOn,
            styleInner: { range in
                storage.addAttribute(.font, value: boldFont(size: fontSize), range: range)
            }
        )
        applyWrappedMarkdown(
            to: storage,
            content: content,
            selectedRange: selectedRange,
            open: "~~",
            close: "~~",
            hiddenDelimiterOn: hiddenDelimiterOn,
            styleInner: { range in
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        )
        applyWrappedMarkdown(
            to: storage,
            content: content,
            selectedRange: selectedRange,
            open: "==",
            close: "==",
            hiddenDelimiterOn: hiddenDelimiterOn,
            styleInner: { range in
                storage.addAttribute(.backgroundColor, value: highlight, range: range)
            }
        )
        applyWrappedMarkdown(
            to: storage,
            content: content,
            selectedRange: selectedRange,
            open: "`",
            close: "`",
            hiddenDelimiterOn: hiddenDelimiterOn,
            styleInner: { range in
                storage.addAttribute(.font, value: monoFont(size: fontSize), range: range)
            }
        )
        applyWrappedMarkdown(
            to: storage,
            content: content,
            selectedRange: selectedRange,
            open: "*",
            close: "*",
            hiddenDelimiterOn: hiddenDelimiterOn,
            styleInner: { range in
                storage.addAttribute(.font, value: italicFont(size: fontSize), range: range)
            },
            skipIfPrefixedBy: "*"
        )
    }

    private static func applyWrappedMarkdown(
        to storage: NSMutableAttributedString,
        content: NSString,
        selectedRange: NSRange,
        open: String,
        close: String,
        hiddenDelimiterOn: Color,
        styleInner: (NSRange) -> Void,
        skipIfPrefixedBy: String? = nil
    ) {
        let hidden = platformColor(hiddenDelimiterOn)
        let muted = platformColor(bracketColor)
        var searchStart = 0

        while searchStart < content.length {
            let tail = NSRange(location: searchStart, length: content.length - searchStart)
            let openRange = content.range(of: open, options: [], range: tail)
            guard openRange.location != NSNotFound else { break }

            if let prefix = skipIfPrefixedBy, openRange.location > 0 {
                let prefixIndex = openRange.location - 1
                if content.substring(with: NSRange(location: prefixIndex, length: 1)) == prefix {
                    searchStart = openRange.location + open.count
                    continue
                }
            }

            let afterOpen = NSRange(location: openRange.location + open.count, length: content.length - openRange.location - open.count)
            let closeRange = content.range(of: close, options: [], range: afterOpen)
            guard closeRange.location != NSNotFound else { break }

            let inner = NSRange(location: openRange.location + open.count, length: closeRange.location - openRange.location - open.count)
            let full = NSRange(location: openRange.location, length: closeRange.location + close.count - openRange.location)
            let isEditing = selectedRange.location != NSNotFound && NSIntersectionRange(full, selectedRange).length > 0
            let delimiterPaint = isEditing ? muted : hidden

            storage.addAttribute(.foregroundColor, value: delimiterPaint, range: openRange)
            storage.addAttribute(.foregroundColor, value: delimiterPaint, range: closeRange)
            if inner.length > 0 {
                styleInner(inner)
            }
            searchStart = closeRange.location + close.count
        }
    }

    #if canImport(AppKit)
    private static func boldFont(size: CGFloat) -> NSFont {
        NSFont.boldSystemFont(ofSize: size)
    }

    private static func italicFont(size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
    }

    private static func monoFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    #else
    private static func boldFont(size: CGFloat) -> UIFont {
        UIFont.boldSystemFont(ofSize: size)
    }

    private static func italicFont(size: CGFloat) -> UIFont {
        UIFont.italicSystemFont(ofSize: size)
    }

    private static func monoFont(size: CGFloat) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    #endif

    private static func applyWikilinkStyling(
        to storage: NSMutableAttributedString,
        selectedRange: NSRange,
        hiddenDelimiterOn: Color = AppColors.canvasBackground
    ) {
        let content = storage.string as NSString
        guard content.length > 0 else { return }

        let bracket = platformColor(bracketColor)
        let hiddenBracket = platformColor(hiddenDelimiterOn)
        let link = platformColor(linkColor)
        var index = 0

        while index < content.length {
            let tail = NSRange(location: index, length: content.length - index)
            let open = content.range(of: "[[", options: [], range: tail)
            guard open.location != NSNotFound else { break }

            let afterOpen = NSRange(location: open.location + 2, length: content.length - open.location - 2)
            let close = content.range(of: "]]", options: [], range: afterOpen)

            let isComplete = close.location != NSNotFound
            let isEditing = isEditingWikilink(
                open: open,
                close: isComplete ? close : nil,
                selectedRange: selectedRange
            )

            let bracketPaint = (isComplete && !isEditing) ? hiddenBracket : bracket
            storage.addAttribute(.foregroundColor, value: bracketPaint, range: open)

            let inner: NSRange
            if isComplete {
                inner = NSRange(location: open.location + 2, length: close.location - open.location - 2)
                storage.addAttribute(.foregroundColor, value: bracketPaint, range: close)
                index = close.location + 2
            } else {
                inner = NSRange(location: open.location + 2, length: content.length - open.location - 2)
                index = content.length
            }

            guard inner.length > 0 else { continue }

            storage.addAttribute(.foregroundColor, value: link, range: inner)

            let cursorInsideInner = selectedRange.location != NSNotFound
                && NSIntersectionRange(inner, selectedRange).length > 0
            let shouldUnderline = (isComplete && !isEditing) || cursorInsideInner
            if shouldUnderline {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: inner)
                storage.addAttribute(.underlineColor, value: link, range: inner)
            }
        }
    }

    /// Brackets stay visible only while the cursor is inside an incomplete or active `[[...]]`.
    private static func isEditingWikilink(
        open: NSRange,
        close: NSRange?,
        selectedRange: NSRange
    ) -> Bool {
        guard selectedRange.location != NSNotFound else { return false }
        guard let close else { return true }

        let fullRange = NSRange(location: open.location, length: close.location + 2 - open.location)
        return NSIntersectionRange(fullRange, selectedRange).length > 0
    }
}
