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
        if let embed = activeBracketQuery(in: content, cursor: cursor, openMarker: "![[", openLength: 3) {
            return embed
        }
        return activeBracketQuery(in: content, cursor: cursor, openMarker: "[[", openLength: 2)
    }

    private static func activeBracketQuery(
        in content: String,
        cursor: Int,
        openMarker: String,
        openLength: Int
    ) -> WikilinkActiveQuery? {
        let ns = content as NSString
        let clampedCursor = min(max(cursor, 0), ns.length)
        guard clampedCursor >= openLength else { return nil }

        let searchRange = NSRange(location: 0, length: clampedCursor)
        let openRange = ns.range(of: openMarker, options: .backwards, range: searchRange)
        guard openRange.location != NSNotFound else { return nil }

        let typedRange = NSRange(
            location: openRange.location + openLength,
            length: clampedCursor - openRange.location - openLength
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
        let isEmbed = replaceRange.location + 3 <= ns.length
            && ns.substring(with: NSRange(location: replaceRange.location, length: 3)) == "![["
        let insertion = isEmbed ? "![[\(target)]]" : "[[\(target)]]"
        let newText = ns.replacingCharacters(in: replaceRange, with: insertion)
        let cursor = replaceRange.location + (insertion as NSString).length
        return (newText, cursor)
    }

    static func previewAttributedString(from content: String) -> AttributedString {
        AttributedString(displayAttributedString(from: content))
    }

    /// Preview/readonly surfaces strip hidden delimiter characters — SwiftUI `Text` ignores zero-width font tricks.
    static func displayAttributedString(
        from content: String,
        selectedRange: NSRange = NSRange(location: NSNotFound, length: 0),
        fontSize: CGFloat = bodyFontSize,
        hiddenDelimiterOn: Color = AppColors.canvasBackground,
        hideTaskListMarkers: Bool = false
    ) -> NSAttributedString {
        let styled = attributedString(
            for: content,
            selectedRange: selectedRange,
            fontSize: fontSize,
            hiddenDelimiterOn: hiddenDelimiterOn,
            hideTaskListMarkers: hideTaskListMarkers
        )
        return removingHiddenDelimiterCharacters(from: styled)
    }

    static func removingHiddenDelimiterCharacters(from source: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: source)
        var rangesToDelete: [NSRange] = []
        source.enumerateAttribute(.font, in: NSRange(location: 0, length: source.length)) { value, range, _ in
            guard let font = value else { return }
            #if canImport(AppKit)
            let size = (font as? NSFont)?.pointSize ?? 16
            #else
            let size = (font as? UIFont)?.pointSize ?? 16
            #endif
            if size <= 0.02 {
                rangesToDelete.append(range)
            }
        }
        for range in rangesToDelete.sorted(by: { $0.location > $1.location }) {
            mutable.deleteCharacters(in: range)
        }
        return mutable
    }

    static func attributedString(
        for content: String,
        selectedRange: NSRange,
        fontSize: CGFloat = bodyFontSize,
        hiddenDelimiterOn: Color = AppColors.canvasBackground,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil,
        hideTaskListMarkers: Bool = false
    ) -> NSAttributedString {
        let storage = NSMutableAttributedString(
            string: content,
            attributes: baseBodyAttributes(fontSize: fontSize)
        )
        restyleInPlace(
            storage,
            selectedRange: selectedRange,
            fontSize: fontSize,
            hiddenDelimiterOn: hiddenDelimiterOn,
            vaultURL: vaultURL,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            imageEmbedMaxWidth: imageEmbedMaxWidth,
            hideTaskListMarkers: hideTaskListMarkers
        )
        return storage
    }

    /// Updates markdown/wikilink attributes without replacing plain text — preserves NSTextView undo.
    static func restyleInPlace(
        _ storage: NSMutableAttributedString,
        selectedRange: NSRange,
        fontSize: CGFloat = bodyFontSize,
        hiddenDelimiterOn: Color = AppColors.canvasBackground,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil,
        hideTaskListMarkers: Bool = false
    ) {
        guard storage.length > 0 else { return }
        let resetRanges = NoteImageEmbedAttributedSupport.textRangesExcludingInlineImageAttachments(in: storage)
        for range in resetRanges where range.length > 0 {
            storage.setAttributes(baseBodyAttributes(fontSize: fontSize), range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.backgroundColor, range: range)
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.underlineColor, range: range)
            storage.removeAttribute(.paragraphStyle, range: range)
        }
        applyInlineMarkdownStyling(
            to: storage,
            selectedRange: selectedRange,
            fontSize: fontSize,
            hiddenDelimiterOn: hiddenDelimiterOn
        )
        applyTaskListStyling(to: storage, fontSize: fontSize)
        if hideTaskListMarkers {
            applyTaskListMarkerHiding(
                to: storage,
                fontSize: fontSize,
                hiddenDelimiterOn: hiddenDelimiterOn
            )
        }
        stripDecorationsFromHiddenDelimiters(in: storage)
        applyWikilinkStyling(
            to: storage,
            selectedRange: selectedRange,
            fontSize: fontSize,
            hiddenDelimiterOn: hiddenDelimiterOn,
            vaultURL: vaultURL,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        )
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
            fontSize: fontSize,
            open: "***",
            close: "***",
            hiddenDelimiterOn: hiddenDelimiterOn,
            styleInner: { range in
                storage.addAttribute(.font, value: boldItalicFont(size: fontSize), range: range)
            }
        )
        applyWrappedMarkdown(
            to: storage,
            content: content,
            selectedRange: selectedRange,
            fontSize: fontSize,
            open: "**",
            close: "**",
            hiddenDelimiterOn: hiddenDelimiterOn,
            styleInner: { range in
                storage.addAttribute(.font, value: boldFont(size: fontSize), range: range)
            },
            skipIfPrefixedBy: "*",
            skipIfSuffixedBy: "*"
        )
        applyWrappedMarkdown(
            to: storage,
            content: content,
            selectedRange: selectedRange,
            fontSize: fontSize,
            open: "~~",
            close: "~~",
            hiddenDelimiterOn: hiddenDelimiterOn,
            styleInner: { range in
                applyStrikethrough(to: storage, range: range)
            }
        )
        applyWrappedMarkdown(
            to: storage,
            content: content,
            selectedRange: selectedRange,
            fontSize: fontSize,
            open: "==",
            close: "==",
            hiddenDelimiterOn: hiddenDelimiterOn,
            styleInner: { range in
                applyHighlight(highlight, to: storage, range: range)
            }
        )
        applyWrappedMarkdown(
            to: storage,
            content: content,
            selectedRange: selectedRange,
            fontSize: fontSize,
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
            fontSize: fontSize,
            open: "*",
            close: "*",
            hiddenDelimiterOn: hiddenDelimiterOn,
            styleInner: { range in
                storage.addAttribute(.font, value: italicFont(size: fontSize), range: range)
            },
            skipIfPrefixedBy: "*",
            skipIfSuffixedBy: "*"
        )
    }

    private static let inlineMarkdownDelimiterScalars = CharacterSet(charactersIn: "*~=`")

    private static func applyStrikethrough(to storage: NSMutableAttributedString, range: NSRange) {
        applyDecoration(
            to: storage,
            range: range,
            applyToCharacter: { charRange in
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: charRange)
            }
        )
    }

    private static func applyTaskListStyling(to storage: NSMutableAttributedString, fontSize: CGFloat) {
        let content = storage.string as NSString
        let pattern = #"^\s*[-*+]\s+\[([ xX])\]\s+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        var location = 0
        while location < content.length {
            let lineRange = content.lineRange(for: NSRange(location: location, length: 0))
            let line = content.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let nsLine = line as NSString

            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
               match.numberOfRanges >= 3 {
                let mark = nsLine.substring(with: match.range(at: 1))
                if mark.lowercased() == "x", match.range(at: 2).length > 0 {
                    let bodyRange = NSRange(
                        location: lineRange.location + match.range(at: 2).location,
                        length: match.range(at: 2).length
                    )
                    applyStrikethrough(to: storage, range: bodyRange)
                    #if canImport(AppKit)
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: bodyRange)
                    #else
                    storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: bodyRange)
                    #endif
                }
            }

            location = NSMaxRange(lineRange)
        }
    }

    /// Collapses `- [ ]` / `- [x]` list prefixes when canvas preview draws its own checkbox UI.
    private static func applyTaskListMarkerHiding(
        to storage: NSMutableAttributedString,
        fontSize: CGFloat,
        hiddenDelimiterOn: Color
    ) {
        let content = storage.string as NSString
        let pattern = #"^(\s*[-*+]\s+\[)([ xX])(\]\s+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        var location = 0
        while location < content.length {
            let lineRange = content.lineRange(for: NSRange(location: location, length: 0))
            let line = content.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let nsLine = line as NSString

            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
               match.numberOfRanges >= 4 {
                let prefixStart = match.range(at: 1).location
                let prefixEnd = NSMaxRange(match.range(at: 3))
                let prefixRange = NSRange(
                    location: lineRange.location + prefixStart,
                    length: prefixEnd - prefixStart
                )
                applyDelimiterAppearance(
                    to: storage,
                    range: prefixRange,
                    isEditing: false,
                    fontSize: fontSize,
                    hiddenDelimiterOn: hiddenDelimiterOn
                )

                let leadingInset = NoteCardTaskSupport.lineLeadingInset(fontSize: fontSize)
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = leadingInset
                style.headIndent = leadingInset
                storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
            }

            location = NSMaxRange(lineRange)
        }
    }

    private static func applyHighlight(_ color: Any, to storage: NSMutableAttributedString, range: NSRange) {
        applyDecoration(
            to: storage,
            range: range,
            applyToCharacter: { charRange in
                storage.addAttribute(.backgroundColor, value: color, range: charRange)
            }
        )
    }

    /// Skip markdown delimiter characters so strikethrough/highlight don't bleed past visible text.
    private static func applyDecoration(
        to storage: NSMutableAttributedString,
        range: NSRange,
        applyToCharacter: (NSRange) -> Void
    ) {
        let text = (storage.string as NSString).substring(with: range)
        var offset = range.location
        for character in text {
            let charRange = NSRange(location: offset, length: 1)
            if let scalar = character.unicodeScalars.first,
               !inlineMarkdownDelimiterScalars.contains(scalar) {
                applyToCharacter(charRange)
            }
            offset += 1
        }
    }

    private static func stripDecorationsFromHiddenDelimiters(in storage: NSMutableAttributedString) {
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let font = value else { return }
            #if canImport(AppKit)
            let size = (font as? NSFont)?.pointSize ?? 16
            #else
            let size = (font as? UIFont)?.pointSize ?? 16
            #endif
            guard size <= 0.02 else { return }
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.backgroundColor, range: range)
        }
    }

    /// Hidden markdown delimiters stay in the plain text for persistence, but collapse to ~zero layout width.
    private static func applyDelimiterAppearance(
        to storage: NSMutableAttributedString,
        range: NSRange,
        isEditing: Bool,
        fontSize: CGFloat,
        hiddenDelimiterOn: Color
    ) {
        guard range.length > 0 else { return }
        if isEditing {
            storage.addAttribute(.foregroundColor, value: platformColor(bracketColor), range: range)
            return
        }

        #if canImport(AppKit)
        let hiddenFont = NSFont.systemFont(ofSize: 0.01)
        #else
        let hiddenFont = UIFont.systemFont(ofSize: 0.01)
        #endif
        let charWidth = approximateCharacterWidth(for: fontSize)
        storage.addAttributes([
            .font: hiddenFont,
            .foregroundColor: platformColor(hiddenDelimiterOn),
            .kern: -charWidth * CGFloat(range.length),
        ], range: range)
    }

    private static func approximateCharacterWidth(for fontSize: CGFloat) -> CGFloat {
        #if canImport(AppKit)
        let font = NSFont.systemFont(ofSize: fontSize)
        #else
        let font = UIFont.systemFont(ofSize: fontSize)
        #endif
        return ("*" as NSString).size(withAttributes: [.font: font]).width
    }

    private static func applyWrappedMarkdown(
        to storage: NSMutableAttributedString,
        content: NSString,
        selectedRange: NSRange,
        fontSize: CGFloat,
        open: String,
        close: String,
        hiddenDelimiterOn: Color,
        styleInner: (NSRange) -> Void,
        skipIfPrefixedBy: String? = nil,
        skipIfSuffixedBy: String? = nil
    ) {
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

            if let suffix = skipIfSuffixedBy {
                let suffixIndex = openRange.location + open.count
                if suffixIndex < content.length,
                   content.substring(with: NSRange(location: suffixIndex, length: 1)) == suffix {
                    searchStart = openRange.location + open.count
                    continue
                }
            }

            let afterOpen = NSRange(location: openRange.location + open.count, length: content.length - openRange.location - open.count)
            let closeRange = content.range(of: close, options: [], range: afterOpen)
            guard closeRange.location != NSNotFound else { break }

            if let prefix = skipIfPrefixedBy, closeRange.location > 0 {
                let prefixIndex = closeRange.location - 1
                if content.substring(with: NSRange(location: prefixIndex, length: 1)) == prefix {
                    searchStart = closeRange.location + close.count
                    continue
                }
            }

            if let suffix = skipIfSuffixedBy {
                let suffixIndex = closeRange.location + close.count
                if suffixIndex < content.length,
                   content.substring(with: NSRange(location: suffixIndex, length: 1)) == suffix {
                    searchStart = closeRange.location + close.count
                    continue
                }
            }

            let inner = NSRange(location: openRange.location + open.count, length: closeRange.location - openRange.location - open.count)
            let full = NSRange(location: openRange.location, length: closeRange.location + close.count - openRange.location)
            let isEditing = selectedRange.location != NSNotFound && NSIntersectionRange(full, selectedRange).length > 0

            applyDelimiterAppearance(
                to: storage,
                range: openRange,
                isEditing: isEditing,
                fontSize: fontSize,
                hiddenDelimiterOn: hiddenDelimiterOn
            )
            applyDelimiterAppearance(
                to: storage,
                range: closeRange,
                isEditing: isEditing,
                fontSize: fontSize,
                hiddenDelimiterOn: hiddenDelimiterOn
            )
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

    private static func boldItalicFont(size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(NSFont.boldSystemFont(ofSize: size), toHaveTrait: .italicFontMask)
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

    private static func boldItalicFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
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
        fontSize: CGFloat = bodyFontSize,
        hiddenDelimiterOn: Color = AppColors.canvasBackground,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil
    ) {
        let content = storage.string as NSString
        guard content.length > 0 else { return }

        let link = platformColor(linkColor)
        var index = 0

        while index < content.length {
            let tail = NSRange(location: index, length: content.length - index)
            let embedMarker = content.range(of: "![[", options: [], range: tail)
            let linkMarker = content.range(of: "[[", options: [], range: tail)

            let open: NSRange
            let openLength: Int

            if embedMarker.location != NSNotFound,
               linkMarker.location == NSNotFound || embedMarker.location <= linkMarker.location {
                open = embedMarker
                openLength = 3
            } else if linkMarker.location != NSNotFound {
                if linkMarker.location > 0,
                   content.substring(with: NSRange(location: linkMarker.location - 1, length: 1)) == "!" {
                    index = linkMarker.location + 1
                    continue
                }
                open = linkMarker
                openLength = 2
            } else {
                break
            }

            let afterOpen = NSRange(location: open.location + openLength, length: content.length - open.location - openLength)
            let close = content.range(of: "]]", options: [], range: afterOpen)

            let isComplete = close.location != NSNotFound
            let isEditing = isEditingWikilink(
                open: open,
                close: isComplete ? close : nil,
                closeLength: 2,
                selectedRange: selectedRange
            )

            applyDelimiterAppearance(
                to: storage,
                range: open,
                isEditing: !isComplete || isEditing,
                fontSize: fontSize,
                hiddenDelimiterOn: hiddenDelimiterOn
            )

            let inner: NSRange
            if isComplete {
                inner = NSRange(location: open.location + openLength, length: close.location - open.location - openLength)
                applyDelimiterAppearance(
                    to: storage,
                    range: close,
                    isEditing: isEditing,
                    fontSize: fontSize,
                    hiddenDelimiterOn: hiddenDelimiterOn
                )
                index = close.location + 2
            } else {
                inner = NSRange(location: open.location + openLength, length: content.length - open.location - openLength)
                index = content.length
            }

            guard inner.length > 0 else { continue }

            let innerText = content.substring(with: inner)
            let embedTarget = innerText
                .components(separatedBy: "|").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? innerText
            let isImageEmbed = VaultFilesystem.isImageEmbedTarget(embedTarget)
                && vaultURL != nil
            if hideResolvedImageEmbeds, isImageEmbed, isComplete {
                let full = NSRange(location: open.location, length: close.location + 2 - open.location)
                applyDelimiterAppearance(
                    to: storage,
                    range: full,
                    isEditing: false,
                    fontSize: fontSize,
                    hiddenDelimiterOn: hiddenDelimiterOn
                )
                if let imageEmbedMaxWidth, vaultURL != nil {
                    let path = VaultFilesystem.preferredCanvasAssetPath(for: embedTarget)
                    let imageHeight = ceil(
                        NoteCardEmbedLayoutMetrics.reservedHeight(
                            for: path,
                            maxWidth: imageEmbedMaxWidth,
                            vaultURL: vaultURL
                        )
                    )

                    let embedParagraph = content.paragraphRange(for: full)
                    let embedStyle = NSMutableParagraphStyle()
                    embedStyle.minimumLineHeight = imageHeight
                    embedStyle.maximumLineHeight = imageHeight
                    embedStyle.lineSpacing = 0
                    embedStyle.paragraphSpacing = NoteCardContentLayout.rowSpacing
                    embedStyle.paragraphSpacingBefore = 0
                    storage.addAttribute(.paragraphStyle, value: embedStyle, range: embedParagraph)

                    let afterEmbed = NSMaxRange(embedParagraph)
                    if afterEmbed < content.length {
                        let nextParagraph = content.paragraphRange(for: NSRange(location: afterEmbed, length: 0))
                        if nextParagraph.length > 0 {
                            let nextStyle = NSMutableParagraphStyle()
                            if let existing = storage.attribute(.paragraphStyle, at: nextParagraph.location, effectiveRange: nil) as? NSParagraphStyle {
                                nextStyle.setParagraphStyle(existing)
                            }
                            nextStyle.paragraphSpacingBefore = NoteCardContentLayout.rowSpacing
                            storage.addAttribute(.paragraphStyle, value: nextStyle, range: nextParagraph)
                        }
                    }
                }
                continue
            }

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

    /// Brackets stay visible only while the cursor is inside an incomplete or active link/embed.
    private static func isEditingWikilink(
        open: NSRange,
        close: NSRange?,
        closeLength: Int = 2,
        selectedRange: NSRange
    ) -> Bool {
        guard selectedRange.location != NSNotFound else { return false }
        guard let close else { return true }

        let fullRange = NSRange(location: open.location, length: close.location + closeLength - open.location)
        return NSIntersectionRange(fullRange, selectedRange).length > 0
    }
}
