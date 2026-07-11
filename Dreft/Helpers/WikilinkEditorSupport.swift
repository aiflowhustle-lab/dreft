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

    static func attributedString(for content: String, selectedRange: NSRange) -> NSAttributedString {
        let storage = NSMutableAttributedString(
            string: content,
            attributes: baseBodyAttributes()
        )
        applyWikilinkStyling(to: storage, selectedRange: selectedRange)
        return storage
    }

    private static func baseBodyAttributes() -> [NSAttributedString.Key: Any] {
        #if canImport(AppKit)
        let font = NSFont.systemFont(ofSize: bodyFontSize)
        let color = NSColor(textColorForPlatform)
        #else
        let font = UIFont.systemFont(ofSize: bodyFontSize)
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

    private static func applyWikilinkStyling(
        to storage: NSMutableAttributedString,
        selectedRange: NSRange
    ) {
        let content = storage.string as NSString
        guard content.length > 0 else { return }

        let bracket = platformColor(bracketColor)
        let hiddenBracket = platformColor(hiddenBracketColor)
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
