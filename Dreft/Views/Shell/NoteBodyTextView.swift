import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
@preconcurrency import AppKit
#elseif canImport(UIKit)
@preconcurrency import UIKit
#endif

enum WikilinkSuggestKey {
    case up
    case down
    case enter
    case escape
}

protocol NoteEditingTextViewDelegate: AnyObject {
    func noteTextViewDidApplyEdit(_ textView: AnyObject)
}

enum NoteEditingChromeSupport {
    #if os(macOS)
    static func selectionRects(in textView: NSTextView) -> [CGRect] {
        let range = textView.selectedRange()
        guard range.length > 0,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return [] }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rects: [CGRect] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: glyphRange,
            in: textContainer
        ) { rect, _ in
            rects.append(convert(rect, in: textView))
        }
        return rects
    }

    static func caretRect(in textView: NSTextView, fontSize: CGFloat) -> CGRect {
        let layoutView = layoutTextView(for: textView)

        guard let layoutManager = layoutView.layoutManager ?? textView.layoutManager,
              let textContainer = layoutView.textContainer ?? textView.textContainer else { return .zero }

        let selected = textView.selectedRange()
        let caretIndex = min(
            max(0, selected.location + max(selected.length, 0)),
            (textView.string as NSString).length
        )

        var glyphIndex = layoutManager.glyphIndexForCharacter(at: caretIndex)
        if glyphIndex >= layoutManager.numberOfGlyphs {
            glyphIndex = max(0, layoutManager.numberOfGlyphs - 1)
        }

        var rect = layoutManager.boundingRect(
            forGlyphRange: NSRange(
                location: glyphIndex,
                length: min(1, max(0, layoutManager.numberOfGlyphs - glyphIndex))
            ),
            in: textContainer
        )
        if rect.height < 1 {
            rect.size.height = fontSize * 1.2
        }
        return convert(rect, in: textView, layoutView: layoutView)
    }

    /// Anchor for wikilink suggest — left edge at `[[`, vertical at line bottom.
    static func wikilinkSuggestAnchor(in textView: NSTextView, characterIndex: Int, fontSize: CGFloat) -> CGRect {
        let layoutView = layoutTextView(for: textView)

        guard let layoutManager = layoutView.layoutManager ?? textView.layoutManager,
              let textContainer = layoutView.textContainer ?? textView.textContainer else { return .zero }

        let length = (textView.string as NSString).length
        let index = min(max(0, characterIndex), length)
        var glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
        if glyphIndex >= layoutManager.numberOfGlyphs {
            glyphIndex = max(0, layoutManager.numberOfGlyphs - 1)
        }

        var lineGlyphRange = NSRange()
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
        var charRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(
                location: glyphIndex,
                length: min(1, max(0, layoutManager.numberOfGlyphs - glyphIndex))
            ),
            in: textContainer
        )
        if charRect.height < 1 {
            charRect.size.height = fontSize * 1.2
        }

        let convertedLine = convert(lineRect, in: textView, layoutView: layoutView)
        let convertedChar = convert(charRect, in: textView, layoutView: layoutView)
        return CGRect(x: convertedChar.minX, y: convertedLine.maxY, width: 0, height: 0)
    }

    private static func layoutTextView(for textView: NSTextView) -> NSTextView {
        guard let window = textView.window,
              let fieldEditor = window.fieldEditor(false, for: textView) as? NSTextView,
              window.firstResponder === fieldEditor else {
            return textView
        }
        return fieldEditor
    }

    private static func convert(_ rect: CGRect, in textView: NSTextView, layoutView: NSTextView? = nil) -> CGRect {
        let layoutView = layoutView ?? textView
        var converted = rect
        converted.origin.x += layoutView.textContainerInset.width
        converted.origin.y += layoutView.textContainerInset.height
        if layoutView !== textView {
            converted = layoutView.convert(converted, to: textView)
        }
        if let scrollView = textView.enclosingScrollView {
            let scrollOrigin = scrollView.contentView.bounds.origin
            converted.origin.x -= scrollOrigin.x
            converted.origin.y -= scrollOrigin.y
        }
        return converted
    }
    #elseif os(iOS)
    static func selectionRects(in textView: UITextView, contentScrollOffset: CGPoint? = nil) -> [CGRect] {
        guard let range = textView.selectedTextRange, !range.isEmpty else { return [] }
        let scrollOffset = contentScrollOffset ?? textView.contentOffset
        return textView.selectionRects(for: range).map { item in
            var rect = item.rect
            rect.origin.x -= scrollOffset.x
            rect.origin.y -= scrollOffset.y
            rect.origin.x += textView.textContainerInset.left
            rect.origin.y += textView.textContainerInset.top
            return rect
        }
    }

    static func caretRect(in textView: UITextView, fontSize: CGFloat, contentScrollOffset: CGPoint? = nil) -> CGRect {
        guard let range = textView.selectedTextRange else { return .zero }
        let scrollOffset = contentScrollOffset ?? textView.contentOffset
        var rect = textView.caretRect(for: range.end)
        rect.origin.x -= scrollOffset.x
        rect.origin.y -= scrollOffset.y
        rect.origin.x += textView.textContainerInset.left
        rect.origin.y += textView.textContainerInset.top
        if rect.height < 1 {
            rect.size.height = fontSize * 1.2
        }
        return rect
    }

    static func documentCaretRect(in textView: UITextView, fontSize: CGFloat) -> CGRect {
        caretRect(in: textView, fontSize: fontSize, contentScrollOffset: .zero)
    }

    /// Aligns a task checkbox overlay with the first visible character on a task row.
    static func checkboxOrigin(
        forCharacterIndex index: Int,
        in textView: UITextView,
        contentScrollOffset: CGPoint,
        fontSize: CGFloat
    ) -> CGPoint {
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let length = (textView.text as NSString?)?.length ?? 0
        let clampedIndex = min(max(0, index), length)

        layoutManager.ensureLayout(for: textContainer)

        var glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedIndex)
        if glyphIndex >= layoutManager.numberOfGlyphs {
            glyphIndex = max(0, layoutManager.numberOfGlyphs - 1)
        }

        let baselineY = layoutManager.location(forGlyphAt: glyphIndex).y
        let checkboxSize = NoteCardTaskSupport.scaledCheckboxWidth(fontSize: fontSize)
        let alignmentOffset = NoteCardTaskSupport.checkboxBaselineAlignmentOffset(fontSize: fontSize)
        let checkboxTop = baselineY - checkboxSize + alignmentOffset

        return CGPoint(
            x: 0,
            y: checkboxTop + textView.textContainerInset.top - contentScrollOffset.y
        )
    }

    static func wikilinkSuggestAnchor(
        in textView: UITextView,
        characterIndex: Int,
        fontSize: CGFloat,
        contentScrollOffset: CGPoint? = nil
    ) -> CGRect {
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer

        let scrollOffset = contentScrollOffset ?? textView.contentOffset
        let length = (textView.text as NSString?)?.length ?? 0
        let index = min(max(0, characterIndex), length)
        var glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
        if glyphIndex >= layoutManager.numberOfGlyphs {
            glyphIndex = max(0, layoutManager.numberOfGlyphs - 1)
        }

        var lineGlyphRange = NSRange()
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
        var charRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(
                location: glyphIndex,
                length: min(1, max(0, layoutManager.numberOfGlyphs - glyphIndex))
            ),
            in: textContainer
        )
        if charRect.height < 1 {
            charRect.size.height = fontSize * 1.2
        }

        var lineBottom = lineRect
        lineBottom.origin.x -= scrollOffset.x
        lineBottom.origin.y -= scrollOffset.y
        lineBottom.origin.x += textView.textContainerInset.left
        lineBottom.origin.y += textView.textContainerInset.top

        var charOrigin = charRect
        charOrigin.origin.x -= scrollOffset.x
        charOrigin.origin.y -= scrollOffset.y
        charOrigin.origin.x += textView.textContainerInset.left
        charOrigin.origin.y += textView.textContainerInset.top

        return CGRect(x: charOrigin.minX, y: lineBottom.maxY, width: 0, height: 0)
    }
    #endif
}

struct NoteBodyTextView: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var caretRect: CGRect
    @Binding var selectionRects: [CGRect]
    var isFocused: FocusState<Bool>.Binding
    let files: [WorkspaceFileEntry]
    @Binding var suggestSelectedIndex: Int
    var fontSize: CGFloat = WikilinkEditorSupport.bodyFontSize
    var minBodyHeight: CGFloat = 520
    var embeddedInCanvas: Bool = false
    var editorBackground: Color = AppColors.canvasBackground
    var vaultURL: URL? = nil
    var hideResolvedImageEmbeds: Bool = false
    var imageEmbedMaxWidth: CGFloat? = nil
    var hideTaskListMarkers: Bool = false
    /// Plain-text edits; `fromTextUndo` is true for NSTextView/UITextView ⌘Z steps.
    var onTextEdited: ((String, Bool) -> Void)?
    var toolbarBridge: NoteFormattingToolbarBridge? = nil
    var onImageAttachmentDrop: ((Data, String?) -> Bool)? = nil
    var layoutRefreshToken: Int = 0
    var selectionRevealToken: Int = 0
    var onContentScroll: ((CanvasNoteScrollMetrics) -> Void)? = nil
    var fillsAvailableHeight: Bool = false

    @State private var activeQuery: WikilinkActiveQuery?
    @State private var suggestAnchorRect = CGRect.zero
    @State private var wikilinkInsertRevision = 0
    #if os(iOS)
    @State private var keyboardBottomOverlap: CGFloat = 0
    #endif

    private var suggestions: [WorkspaceFileEntry] {
        guard let activeQuery else { return [] }
        return WikilinkSuggestSearch.results(matching: activeQuery.query, in: files)
    }

    private var showsCustomEditingChrome: Bool {
        hideResolvedImageEmbeds
    }

    /// Custom caret overlay — only when native insertion point is hidden (image-embed editing).
    private var showsInlineCaretOverlay: Bool {
        hideResolvedImageEmbeds && !embeddedInCanvas
    }

    private var hidesNativeInsertionPoint: Bool {
        #if os(iOS)
        // Standalone notes use the native blinking caret; hide it only for inline image embeds.
        return hideResolvedImageEmbeds
        #else
        return embeddedInCanvas && hideResolvedImageEmbeds
        #endif
    }

    /// Anchor below the active `[[` line, left-aligned with the brackets.
    private var wikilinkSuggestPopoverOffset: CGSize {
        let verticalGap: CGFloat = 6
        if suggestAnchorRect != .zero {
            return CGSize(width: suggestAnchorRect.minX, height: suggestAnchorRect.minY + verticalGap)
        }
        return CGSize(width: caretRect.minX, height: caretRect.maxY + verticalGap)
    }

    private func clampedWikilinkSuggestOffset(containerSize: CGSize?) -> CGSize {
        let natural = wikilinkSuggestPopoverOffset
        #if os(iOS)
        guard let containerSize, containerSize.height > 0 else { return natural }
        let popoverHeight = WikilinkSuggestPopover.estimatedHeight(resultCount: min(suggestions.count, 8))
        let accessory = NoteFormattingToolbarAccessoryContainer.preferredHeight
        let bottomLimit = containerSize.height - keyboardBottomOverlap - accessory - popoverHeight - 8
        let clampedY = min(natural.height, max(0, bottomLimit))
        return CGSize(width: natural.width, height: clampedY)
        #else
        return natural
        #endif
    }

    private var wikilinkSuggestPassthroughRect: CGRect {
        #if os(macOS)
        guard activeQuery != nil, !suggestions.isEmpty else { return .zero }
        let offset = wikilinkSuggestPopoverOffset
        return CGRect(
            x: offset.width,
            y: offset.height,
            width: WikilinkSuggestPopover.preferredWidth,
            height: WikilinkSuggestPopover.estimatedHeight(resultCount: suggestions.count)
        )
        #else
        return .zero
        #endif
    }

    private var usesFillLayout: Bool {
        embeddedInCanvas || fillsAvailableHeight
    }

    var body: some View {
        Group {
            if usesFillLayout {
                GeometryReader { geometry in
                    editorStack(containerSize: geometry.size)
                }
            } else {
                editorStack(containerSize: nil)
            }
        }
        .onChange(of: text) { _, _ in refreshActiveQuery() }
    }

    @ViewBuilder
    private func editorStack(containerSize: CGSize?) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                #if os(macOS)
                NoteBodyTextViewRepresentable(
                    text: $text,
                    selectedRange: $selectedRange,
                    caretRect: $caretRect,
                    selectionRects: $selectionRects,
                    suggestAnchorRect: $suggestAnchorRect,
                    wikilinkSuggestPassthroughRect: wikilinkSuggestPassthroughRect,
                    wikilinkSuggestResultCount: min(suggestions.count, 8),
                    wikilinkInsertRevision: wikilinkInsertRevision,
                    onSuggestRowSelect: { index in
                        guard index >= 0, index < suggestions.count else { return }
                        insertSuggestion(suggestions[index])
                    },
                    isFocused: isFocused,
                    fontSize: fontSize,
                    embeddedInCanvas: embeddedInCanvas,
                    containerSize: containerSize,
                    editorBackground: editorBackground,
                    vaultURL: vaultURL,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: imageEmbedMaxWidth,
                    hideTaskListMarkers: hideTaskListMarkers,
                    onSelectionChange: refreshActiveQuery,
                    onSuggestKey: handleSuggestKey,
                    onTextEdited: onTextEdited,
                    toolbarBridge: toolbarBridge,
                    onImageAttachmentDrop: onImageAttachmentDrop,
                    layoutRefreshToken: layoutRefreshToken,
                    selectionRevealToken: selectionRevealToken,
                    onContentScroll: onContentScroll
                )
                #else
                NoteBodyTextViewRepresentable(
                    text: $text,
                    selectedRange: $selectedRange,
                    caretRect: $caretRect,
                    selectionRects: $selectionRects,
                    suggestAnchorRect: $suggestAnchorRect,
                    wikilinkInsertRevision: wikilinkInsertRevision,
                    isFocused: isFocused,
                    fontSize: fontSize,
                    embeddedInCanvas: embeddedInCanvas,
                    containerSize: containerSize,
                    editorBackground: editorBackground,
                    vaultURL: vaultURL,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: imageEmbedMaxWidth,
                    hideTaskListMarkers: hideTaskListMarkers,
                    onSelectionChange: refreshActiveQuery,
                    onSuggestKey: handleSuggestKey,
                    onTextEdited: onTextEdited,
                    toolbarBridge: toolbarBridge,
                    onImageAttachmentDrop: onImageAttachmentDrop,
                    layoutRefreshToken: layoutRefreshToken,
                    selectionRevealToken: selectionRevealToken,
                    onContentScroll: onContentScroll,
                    fillsAvailableHeight: fillsAvailableHeight,
                    keyboardBottomOverlap: $keyboardBottomOverlap
                )
                #endif
            }
            .frame(maxWidth: embeddedInCanvas || fillsAvailableHeight ? .infinity : nil, maxHeight: embeddedInCanvas || fillsAvailableHeight ? .infinity : nil)
            .frame(minHeight: embeddedInCanvas || fillsAvailableHeight ? 0 : minBodyHeight)
            .clipShape(RoundedRectangle(cornerRadius: embeddedInCanvas ? 4 : 0))

            if showsInlineCaretOverlay {
                NoteEditingCaretOverlay(
                    caretRect: caretRect,
                    selectionRects: selectionRects,
                    fontSize: fontSize,
                    isVisible: true
                )
                .zIndex(10)
            }

            if activeQuery != nil, !suggestions.isEmpty {
                let suggestOffset = clampedWikilinkSuggestOffset(containerSize: containerSize)
                WikilinkSuggestPopover(
                    results: suggestions,
                    selectedIndex: $suggestSelectedIndex,
                    onSelect: insertSuggestion
                )
                .offset(x: suggestOffset.width, y: suggestOffset.height)
                .fixedSize()
                .zIndex(100)
                .allowsHitTesting(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: embeddedInCanvas || fillsAvailableHeight ? 0 : minBodyHeight, alignment: .topLeading)
    }

    private func refreshActiveQuery() {
        let cursor = selectedRange.location + selectedRange.length
        let query = WikilinkEditorSupport.activeQuery(in: text, cursor: cursor)
        Task { @MainActor in
            if query != activeQuery {
                activeQuery = query
                if query != nil {
                    suggestSelectedIndex = 0
                } else {
                    suggestAnchorRect = .zero
                }
            }
        }
    }

    private func handleSuggestKey(_ key: WikilinkSuggestKey) -> Bool {
        guard activeQuery != nil, !suggestions.isEmpty else { return false }
        switch key {
        case .up:
            suggestSelectedIndex = max(0, suggestSelectedIndex - 1)
            return true
        case .down:
            suggestSelectedIndex = min(suggestions.count - 1, suggestSelectedIndex + 1)
            return true
        case .enter:
            insertSuggestion(suggestions[suggestSelectedIndex])
            return true
        case .escape:
            activeQuery = nil
            return true
        }
    }

    private func insertSuggestion(_ file: WorkspaceFileEntry) {
        guard let query = activeQuery else { return }
        let target = WikilinkEditorSupport.insertTarget(for: file)
        let result = WikilinkEditorSupport.insertSuggestion(target, into: text, replaceRange: query.replaceRange)
        text = result.text
        selectedRange = NSRange(location: result.cursor, length: 0)
        activeQuery = nil
        suggestAnchorRect = .zero
        wikilinkInsertRevision += 1
        onTextEdited?(result.text, false)
    }
}

enum WikilinkSuggestSearch {
    static func results(matching query: String, in files: [WorkspaceFileEntry]) -> [WorkspaceFileEntry] {
        let candidates = files.filter { $0.kind == .note || $0.kind == .canvas || $0.kind == .image }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(candidates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.prefix(12))
        }

        let normalizedQuery = WikilinkParser.normalizedName(trimmed)
        var ranked: [(file: WorkspaceFileEntry, score: Int)] = []

        for file in candidates {
            let label = WikilinkEditorSupport.suggestionLabel(for: file)
            let normalizedLabel = WikilinkParser.normalizedName(label)
            let normalizedPath = WikilinkParser.normalizedName(file.relativePath)
            var score = 0
            if normalizedLabel.hasPrefix(normalizedQuery) {
                score = 300 - normalizedLabel.count
            } else if normalizedLabel.contains(normalizedQuery) {
                score = 180
            } else if normalizedPath.contains(normalizedQuery) {
                score = 120
            }
            if score > 0 {
                ranked.append((file, score))
            }
        }

        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.file.name.localizedStandardCompare(rhs.file.name) == .orderedAscending
        }
        return ranked.prefix(12).map(\.file)
    }
}

/// Balanced undo-registration guard — nested calls won't double-enable and crash.
private enum NoteUndoRegistration {
    static func perform(on undoManager: UndoManager?, _ work: () -> Void) {
        guard let undoManager else {
            work()
            return
        }
        let wasEnabled = undoManager.isUndoRegistrationEnabled
        if wasEnabled {
            undoManager.disableUndoRegistration()
        }
        defer {
            if wasEnabled, !undoManager.isUndoRegistrationEnabled {
                undoManager.enableUndoRegistration()
            }
        }
        work()
    }
}

enum NoteTextEditingCoordinatorSupport {
    static func usesWysiwygEditing(
        embeddedInCanvas: Bool,
        hideResolvedImageEmbeds: Bool,
        vaultURL: URL?,
        imageEmbedMaxWidth: CGFloat?
    ) -> Bool {
        return !NoteImageEmbedAttributedSupport.usesInlineAttachments(
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        )
    }

    static func editingSourceAndRange(
        from textView: AnyObject,
        markdownBinding: String,
        embeddedInCanvas: Bool,
        fontSize: CGFloat,
        editorBackground: Color,
        hideResolvedImageEmbeds: Bool,
        vaultURL: URL?,
        imageEmbedMaxWidth: CGFloat?,
        hideTaskListMarkers: Bool = false
    ) -> (source: String, range: NSRange, usesAttachments: Bool) {
        let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        )
        #if os(macOS)
        guard let textView = textView as? NSTextView else {
            return ("", NSRange(location: 0, length: 0), false)
        }
        if usesAttachments {
            let source = NoteImageEmbedAttributedSupport.markdown(
                from: textView.attributedString(),
                vaultURL: vaultURL
            )
            let range = NoteImageEmbedAttributedSupport.markdownRange(
                fromAttributedRange: textView.selectedRange(),
                in: source,
                vaultURL: vaultURL
            )
            return (source, range, true)
        }
        if usesWysiwygEditing(
            embeddedInCanvas: embeddedInCanvas,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        ) {
            let range = MarkdownWysiwygEditingSupport.markdownRange(
                fromDisplay: textView.selectedRange(),
                in: markdownBinding,
                fontSize: fontSize,
                editorBackground: editorBackground,
                hideTaskListMarkers: hideTaskListMarkers
            )
            return (markdownBinding, range, false)
        }
        return (textView.string, textView.selectedRange(), false)
        #else
        guard let textView = textView as? UITextView else {
            return ("", NSRange(location: 0, length: 0), false)
        }
        if usesAttachments {
            let source = NoteImageEmbedAttributedSupport.markdown(
                from: textView.attributedText,
                vaultURL: vaultURL
            )
            let range = NoteImageEmbedAttributedSupport.markdownRange(
                fromAttributedRange: textView.selectedRange,
                in: source,
                vaultURL: vaultURL
            )
            return (source, range, true)
        }
        if usesWysiwygEditing(
            embeddedInCanvas: embeddedInCanvas,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        ) {
            let range = MarkdownWysiwygEditingSupport.markdownRange(
                fromDisplay: textView.selectedRange,
                in: markdownBinding,
                fontSize: fontSize,
                editorBackground: editorBackground,
                hideTaskListMarkers: hideTaskListMarkers
            )
            return (markdownBinding, range, false)
        }
        return (textView.text ?? "", textView.selectedRange, false)
        #endif
    }

    /// Maps a text-view selection into markdown indices for SwiftUI bindings.
    static func markdownBindingRange(
        fromAttributedRange attributedRange: NSRange,
        markdown: String,
        embeddedInCanvas: Bool,
        fontSize: CGFloat,
        editorBackground: Color,
        hideResolvedImageEmbeds: Bool,
        vaultURL: URL?,
        imageEmbedMaxWidth: CGFloat?,
        hideTaskListMarkers: Bool = false
    ) -> NSRange {
        if NoteImageEmbedAttributedSupport.usesInlineAttachments(
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        ) {
            return NoteImageEmbedAttributedSupport.markdownRange(
                fromAttributedRange: attributedRange,
                in: markdown,
                vaultURL: vaultURL
            )
        }
        if usesWysiwygEditing(
            embeddedInCanvas: embeddedInCanvas,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        ) {
            return MarkdownWysiwygEditingSupport.markdownRange(
                fromDisplay: attributedRange,
                in: markdown,
                fontSize: fontSize,
                editorBackground: editorBackground,
                hideTaskListMarkers: hideTaskListMarkers
            )
        }
        return attributedRange
    }

    static func applySelectedRange(
        _ markdownRange: NSRange,
        markdown: String,
        to textView: AnyObject,
        usesAttachments: Bool,
        embeddedInCanvas: Bool,
        fontSize: CGFloat,
        editorBackground: Color,
        hideResolvedImageEmbeds: Bool,
        imageEmbedMaxWidth: CGFloat?,
        hideTaskListMarkers: Bool,
        vaultURL: URL?
    ) {
        #if os(macOS)
        guard let textView = textView as? NSTextView else { return }
        if usesAttachments {
            textView.setSelectedRange(
                NoteImageEmbedAttributedSupport.attributedRange(
                    fromMarkdownRange: markdownRange,
                    in: markdown,
                    vaultURL: vaultURL
                )
            )
        } else if usesWysiwygEditing(
            embeddedInCanvas: embeddedInCanvas,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        ) {
            textView.setSelectedRange(
                MarkdownWysiwygEditingSupport.displayRange(
                    fromMarkdown: markdownRange,
                    in: markdown,
                    fontSize: fontSize,
                    editorBackground: editorBackground,
                    hideTaskListMarkers: hideTaskListMarkers
                )
            )
        } else {
            textView.setSelectedRange(markdownRange)
        }
        #else
        guard let textView = textView as? UITextView else { return }
        if usesAttachments {
            textView.selectedRange = NoteImageEmbedAttributedSupport.attributedRange(
                fromMarkdownRange: markdownRange,
                in: markdown,
                vaultURL: vaultURL
            )
        } else if usesWysiwygEditing(
            embeddedInCanvas: embeddedInCanvas,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        ) {
            textView.selectedRange = MarkdownWysiwygEditingSupport.displayRange(
                fromMarkdown: markdownRange,
                in: markdown,
                fontSize: fontSize,
                editorBackground: editorBackground,
                hideTaskListMarkers: hideTaskListMarkers
            )
        } else {
            textView.selectedRange = markdownRange
        }
        #endif
    }

    static func styledContent(
        _ content: String,
        selectedRange: NSRange,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL?,
        hideResolvedImageEmbeds: Bool,
        imageEmbedMaxWidth: CGFloat? = nil,
        hideTaskListMarkers: Bool = false,
        embeddedInCanvas: Bool = false
    ) -> NSAttributedString {
        if NoteImageEmbedAttributedSupport.usesInlineAttachments(
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        ), let imageEmbedMaxWidth {
            return NoteImageEmbedAttributedSupport.attributedString(
                from: content,
                selectedRange: selectedRange,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers
            )
        }

        if usesWysiwygEditing(
            embeddedInCanvas: embeddedInCanvas,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        ) {
            return MarkdownWysiwygEditingSupport.displayAttributedString(
                from: content,
                fontSize: fontSize,
                editorBackground: editorBackground,
                hideTaskListMarkers: hideTaskListMarkers
            )
        }

        return WikilinkEditorSupport.attributedString(
            for: content,
            selectedRange: selectedRange,
            fontSize: fontSize,
            hiddenDelimiterOn: editorBackground,
            vaultURL: vaultURL,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            imageEmbedMaxWidth: imageEmbedMaxWidth,
            hideTaskListMarkers: hideTaskListMarkers
        )
    }

    private static func markdownReplacementDelta(from source: String, to result: String) -> (range: NSRange, replacement: String) {
        let oldNS = source as NSString
        let newNS = result as NSString
        var start = 0
        while start < oldNS.length && start < newNS.length && oldNS.character(at: start) == newNS.character(at: start) {
            start += 1
        }
        var oldEnd = oldNS.length
        var newEnd = newNS.length
        while oldEnd > start && newEnd > start && oldNS.character(at: oldEnd - 1) == newNS.character(at: newEnd - 1) {
            oldEnd -= 1
            newEnd -= 1
        }
        let range = NSRange(location: start, length: oldEnd - start)
        let replacement = newNS.substring(with: NSRange(location: start, length: newEnd - start))
        return (range, replacement)
    }

    #if os(macOS)
    private static func applyMarkdownTextMutation(
        to textView: NSTextView,
        source: String,
        result: (text: String, selectedRange: NSRange),
        usesAttachments: Bool,
        embeddedInCanvas: Bool,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL?,
        hideResolvedImageEmbeds: Bool,
        imageEmbedMaxWidth: CGFloat?,
        hideTaskListMarkers: Bool
    ) {
        guard let storage = textView.textStorage else { return }
        textView.undoManager?.beginUndoGrouping()
        defer { textView.undoManager?.endUndoGrouping() }

        let usesWysiwyg = usesWysiwygEditing(
            embeddedInCanvas: embeddedInCanvas,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        )

        if usesAttachments {
            let styled = styledContent(
                result.text,
                selectedRange: result.selectedRange,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers,
                embeddedInCanvas: embeddedInCanvas
            )
            storage.setAttributedString(styled)
        } else if usesWysiwyg {
            storage.setAttributedString(
                styledContent(
                    result.text,
                    selectedRange: NSRange(location: NSNotFound, length: 0),
                    fontSize: fontSize,
                    editorBackground: editorBackground,
                    vaultURL: vaultURL,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: imageEmbedMaxWidth,
                    hideTaskListMarkers: hideTaskListMarkers,
                    embeddedInCanvas: embeddedInCanvas
                )
            )
        } else {
            let (replaceRange, _) = markdownReplacementDelta(from: source, to: result.text)
            let fullStyled = styledContent(
                result.text,
                selectedRange: NSRange(location: NSNotFound, length: 0),
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers,
                embeddedInCanvas: embeddedInCanvas
            )
            let styledReplacement = fullStyled.attributedSubstring(from: replaceRange)
            storage.replaceCharacters(in: replaceRange, with: styledReplacement)
        }

        applySelectedRange(
            result.selectedRange,
            markdown: result.text,
            to: textView,
            usesAttachments: usesAttachments,
            embeddedInCanvas: embeddedInCanvas,
            fontSize: fontSize,
            editorBackground: editorBackground,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            imageEmbedMaxWidth: imageEmbedMaxWidth,
            hideTaskListMarkers: hideTaskListMarkers,
            vaultURL: vaultURL
        )
    }
    #else
    private static func applyMarkdownTextMutation(
        to textView: UITextView,
        source: String,
        result: (text: String, selectedRange: NSRange),
        usesAttachments: Bool,
        embeddedInCanvas: Bool,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL?,
        hideResolvedImageEmbeds: Bool,
        imageEmbedMaxWidth: CGFloat?,
        hideTaskListMarkers: Bool
    ) {
        textView.undoManager?.beginUndoGrouping()
        defer { textView.undoManager?.endUndoGrouping() }

        let usesWysiwyg = usesWysiwygEditing(
            embeddedInCanvas: embeddedInCanvas,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        )

        if usesAttachments {
            textView.attributedText = styledContent(
                result.text,
                selectedRange: result.selectedRange,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers,
                embeddedInCanvas: embeddedInCanvas
            )
        } else if usesWysiwyg {
            textView.attributedText = styledContent(
                result.text,
                selectedRange: NSRange(location: NSNotFound, length: 0),
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers,
                embeddedInCanvas: embeddedInCanvas
            )
        } else {
            let storage = textView.textStorage
            let (replaceRange, _) = markdownReplacementDelta(from: source, to: result.text)
            let fullStyled = styledContent(
                result.text,
                selectedRange: NSRange(location: NSNotFound, length: 0),
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers,
                embeddedInCanvas: embeddedInCanvas
            )
            let styledReplacement = fullStyled.attributedSubstring(from: replaceRange)
            storage.replaceCharacters(in: replaceRange, with: styledReplacement)
        }

        applySelectedRange(
            result.selectedRange,
            markdown: result.text,
            to: textView,
            usesAttachments: usesAttachments,
            embeddedInCanvas: embeddedInCanvas,
            fontSize: fontSize,
            editorBackground: editorBackground,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            imageEmbedMaxWidth: imageEmbedMaxWidth,
            hideTaskListMarkers: hideTaskListMarkers,
            vaultURL: vaultURL
        )
    }
    #endif

    static func applyMarkdownEdit(
        _ action: MarkdownEditAction,
        textView: AnyObject,
        markdownBinding: String,
        embeddedInCanvas: Bool,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil,
        hideTaskListMarkers: Bool = false
    ) -> (text: String, selectedRange: NSRange) {
        let editingState = editingSourceAndRange(
            from: textView,
            markdownBinding: markdownBinding,
            embeddedInCanvas: embeddedInCanvas,
            fontSize: fontSize,
            editorBackground: editorBackground,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth,
            hideTaskListMarkers: hideTaskListMarkers
        )
        let source = editingState.source
        let range = editingState.range
        let usesAttachments = editingState.usesAttachments

        let result = MarkdownEditingSupport.apply(action, text: source, selectedRange: range)

        #if os(macOS)
        guard let textView = textView as? NSTextView else { return ("", NSRange(location: 0, length: 0)) }
        if source != result.text {
            applyMarkdownTextMutation(
                to: textView,
                source: source,
                result: result,
                usesAttachments: usesAttachments,
                embeddedInCanvas: embeddedInCanvas,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers
            )
        } else {
            NoteUndoRegistration.perform(on: textView.undoManager) {
                if !usesWysiwygEditing(
                    embeddedInCanvas: embeddedInCanvas,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    vaultURL: vaultURL,
                    imageEmbedMaxWidth: imageEmbedMaxWidth
                ) {
                    restyleInPlace(
                        textView: textView,
                        fontSize: fontSize,
                        editorBackground: editorBackground,
                        vaultURL: vaultURL,
                        hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                        imageEmbedMaxWidth: imageEmbedMaxWidth,
                        hideTaskListMarkers: hideTaskListMarkers
                    )
                }
                applySelectedRange(
                    result.selectedRange,
                    markdown: result.text,
                    to: textView,
                    usesAttachments: usesAttachments,
                    embeddedInCanvas: embeddedInCanvas,
                    fontSize: fontSize,
                    editorBackground: editorBackground,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: imageEmbedMaxWidth,
                    hideTaskListMarkers: hideTaskListMarkers,
                    vaultURL: vaultURL
                )
            }
        }
        #else
        guard let textView = textView as? UITextView else { return ("", NSRange(location: 0, length: 0)) }
        if source != result.text {
            applyMarkdownTextMutation(
                to: textView,
                source: source,
                result: result,
                usesAttachments: usesAttachments,
                embeddedInCanvas: embeddedInCanvas,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers
            )
        } else {
            NoteUndoRegistration.perform(on: textView.undoManager) {
                if !usesWysiwygEditing(
                    embeddedInCanvas: embeddedInCanvas,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    vaultURL: vaultURL,
                    imageEmbedMaxWidth: imageEmbedMaxWidth
                ) {
                    restyleInPlace(
                        textView: textView,
                        fontSize: fontSize,
                        editorBackground: editorBackground,
                        vaultURL: vaultURL,
                        hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                        imageEmbedMaxWidth: imageEmbedMaxWidth,
                        hideTaskListMarkers: hideTaskListMarkers
                    )
                }
                applySelectedRange(
                    result.selectedRange,
                    markdown: result.text,
                    to: textView,
                    usesAttachments: usesAttachments,
                    embeddedInCanvas: embeddedInCanvas,
                    fontSize: fontSize,
                    editorBackground: editorBackground,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: imageEmbedMaxWidth,
                    hideTaskListMarkers: hideTaskListMarkers,
                    vaultURL: vaultURL
                )
            }
        }
        #endif

        return (result.text, result.selectedRange)
    }

    static func insertSnippet(
        _ snippet: String,
        textView: AnyObject,
        markdownBinding: String,
        embeddedInCanvas: Bool,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil,
        hideTaskListMarkers: Bool = false
    ) -> (text: String, selectedRange: NSRange) {
        let editingState = editingSourceAndRange(
            from: textView,
            markdownBinding: markdownBinding,
            embeddedInCanvas: embeddedInCanvas,
            fontSize: fontSize,
            editorBackground: editorBackground,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth,
            hideTaskListMarkers: hideTaskListMarkers
        )
        let source = editingState.source
        let range = editingState.range
        let usesAttachments = editingState.usesAttachments

        let result = MarkdownEditingSupport.insertText(
            NoteCardEmbedEditingSupport.normalizedAttachmentSnippet(snippet, in: source, range: range),
            in: source,
            range: range
        )
        let sanitized = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(
            in: result.text,
            vaultURL: vaultURL,
            selectedRange: result.selectedRange
        )
        let finalResult = (text: sanitized.text, selectedRange: sanitized.selectedRange ?? result.selectedRange)

        #if os(macOS)
        guard let textView = textView as? NSTextView else { return ("", NSRange(location: 0, length: 0)) }
        applyMarkdownTextMutation(
            to: textView,
            source: source,
            result: finalResult,
            usesAttachments: usesAttachments,
            embeddedInCanvas: embeddedInCanvas,
            fontSize: fontSize,
            editorBackground: editorBackground,
            vaultURL: vaultURL,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            imageEmbedMaxWidth: imageEmbedMaxWidth,
            hideTaskListMarkers: hideTaskListMarkers
        )
        #else
        guard let textView = textView as? UITextView else { return ("", NSRange(location: 0, length: 0)) }
        applyMarkdownTextMutation(
            to: textView,
            source: source,
            result: finalResult,
            usesAttachments: usesAttachments,
            embeddedInCanvas: embeddedInCanvas,
            fontSize: fontSize,
            editorBackground: editorBackground,
            vaultURL: vaultURL,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            imageEmbedMaxWidth: imageEmbedMaxWidth,
            hideTaskListMarkers: hideTaskListMarkers
        )
        #endif

        return (finalResult.text, finalResult.selectedRange)
    }

    static func applyEditedText(
        _ result: (text: String, selectedRange: NSRange),
        textView: AnyObject,
        embeddedInCanvas: Bool,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil,
        hideTaskListMarkers: Bool = false
    ) -> (text: String, selectedRange: NSRange) {
        let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        )
        let styleSelection = usesWysiwygEditing(
            embeddedInCanvas: embeddedInCanvas,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            vaultURL: vaultURL,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        )
            ? NSRange(location: NSNotFound, length: 0)
            : result.selectedRange

        #if os(macOS)
        guard let textView = textView as? NSTextView else { return ("", NSRange(location: 0, length: 0)) }
        NoteUndoRegistration.perform(on: textView.undoManager) {
            let styled = styledContent(
                result.text,
                selectedRange: styleSelection,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers,
                embeddedInCanvas: embeddedInCanvas
            )
            textView.textStorage?.setAttributedString(styled)
            applySelectedRange(
                result.selectedRange,
                markdown: result.text,
                to: textView,
                usesAttachments: usesAttachments,
                embeddedInCanvas: embeddedInCanvas,
                fontSize: fontSize,
                editorBackground: editorBackground,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers,
                vaultURL: vaultURL
            )
        }
        #else
        guard let textView = textView as? UITextView else { return ("", NSRange(location: 0, length: 0)) }
        NoteUndoRegistration.perform(on: textView.undoManager) {
            textView.attributedText = styledContent(
                result.text,
                selectedRange: styleSelection,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers,
                embeddedInCanvas: embeddedInCanvas
            )
            applySelectedRange(
                result.selectedRange,
                markdown: result.text,
                to: textView,
                usesAttachments: usesAttachments,
                embeddedInCanvas: embeddedInCanvas,
                fontSize: fontSize,
                editorBackground: editorBackground,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers,
                vaultURL: vaultURL
            )
        }
        #endif

        return (result.text, result.selectedRange)
    }

    #if os(macOS)
    static func restyleInPlace(
        textView: NSTextView,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil,
        hideTaskListMarkers: Bool = false
    ) {
        if textView.textStorage == nil { return }
        let storage = textView.textStorage!
        let selected = textView.selectedRange()
        NoteUndoRegistration.perform(on: textView.undoManager) {
            storage.beginEditing()
            WikilinkEditorSupport.restyleInPlace(
                storage,
                selectedRange: selected,
                fontSize: fontSize,
                hiddenDelimiterOn: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers
            )
            storage.endEditing()
            if textView.selectedRange() != selected {
                textView.setSelectedRange(selected)
            }
        }
    }
    #else
    static func restyleInPlace(
        textView: UITextView,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil,
        hideTaskListMarkers: Bool = false,
        selectedRangeOverride: NSRange? = nil
    ) {
        let storage = textView.textStorage
        let selected = selectedRangeOverride ?? textView.selectedRange
        NoteUndoRegistration.perform(on: textView.undoManager) {
            storage.beginEditing()
            WikilinkEditorSupport.restyleInPlace(
                storage,
                selectedRange: selected,
                fontSize: fontSize,
                hiddenDelimiterOn: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth,
                hideTaskListMarkers: hideTaskListMarkers
            )
            storage.endEditing()
            if selectedRangeOverride == nil, textView.selectedRange != selected {
                textView.selectedRange = selected
            }
        }
    }
    #endif
}

enum CanvasNoteEditorScrollSupport {
    #if os(macOS)
    static func resetScrollToTop(in textView: NSTextView) {
        guard let scrollView = textView.enclosingScrollView else { return }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    static func scrollCaretIntoViewIfNeeded(_ textView: NSTextView, fontSize: CGFloat) {
        guard let scrollView = textView.enclosingScrollView else { return }
        let caret = NoteEditingChromeSupport.caretRect(in: textView, fontSize: fontSize)
        let visibleHeight = scrollView.contentView.bounds.height
        guard visibleHeight > 0 else { return }

        var offsetY = scrollView.contentView.bounds.origin.y
        let maxOffset = max(0, textView.frame.height - visibleHeight)
        var changed = false
        let margin = max(12, fontSize * 0.4)

        if caret.minY < margin {
            offsetY = max(0, offsetY + caret.minY - margin)
            changed = true
        } else if caret.maxY > visibleHeight - margin {
            offsetY = min(maxOffset, offsetY + caret.maxY - visibleHeight + margin)
            changed = true
        }

        guard changed else { return }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offsetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    #elseif os(iOS)
    static func resetScrollToTop(in scrollView: UIScrollView) {
        scrollView.setContentOffset(.zero, animated: false)
    }

    static func scrollCaretIntoViewIfNeeded(
        _ scrollView: UIScrollView,
        textView: UITextView,
        fontSize: CGFloat
    ) {
        let caret = NoteEditingChromeSupport.documentCaretRect(in: textView, fontSize: fontSize)
        let visibleHeight = scrollView.bounds.height
        guard visibleHeight > 0 else { return }

        let visibleTop = scrollView.contentOffset.y
        let visibleBottom = visibleTop + visibleHeight
        let maxOffset = max(0, scrollView.contentSize.height - visibleHeight)
        var offsetY = scrollView.contentOffset.y
        var changed = false
        let margin = max(12, fontSize * 0.4)

        if caret.minY < visibleTop + margin {
            offsetY = max(0, caret.minY - margin)
            changed = true
        } else if caret.maxY > visibleBottom - margin {
            offsetY = min(maxOffset, caret.maxY - visibleHeight + margin)
            changed = true
        }

        guard changed else { return }
        scrollView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
    }

    static func scrollCaretIntoViewIfNeeded(_ textView: UITextView, fontSize: CGFloat) {
        scrollCaretIntoViewIfNeeded(textView as UIScrollView, textView: textView, fontSize: fontSize)
    }
    #endif
}

#if os(macOS)

final class CanvasNoteScrollView: NSScrollView {
    var onScroll: (() -> Void)?

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        onScroll?()
    }
}

final class CanvasNoteTextContainerView: NSView {
    let scrollView: CanvasNoteScrollView

    var textView: NoteEditingNSTextView {
        scrollView.documentView as! NoteEditingNSTextView
    }

    var onScroll: (() -> Void)? {
        get { scrollView.onScroll }
        set { scrollView.onScroll = newValue }
    }

    init(textView: NoteEditingNSTextView) {
        scrollView = CanvasNoteScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        super.init(frame: .zero)
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
        registerForDraggedTypes(Self.imageDragTypes)
        scrollView.registerForDraggedTypes(Self.imageDragTypes)
    }

    static var imageDragTypes: [NSPasteboard.PasteboardType] {
        NoteEditingNSTextView.imageDragTypes
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        relayoutDocumentTextView()
    }

    func relayoutDocumentTextView() {
        guard let textView = scrollView.documentView as? NSTextView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        let width = max(1, scrollView.contentView.bounds.width)
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let contentHeight = max(used.maxY, scrollView.contentView.bounds.height)
        if abs(textView.frame.width - width) > 0.5 || abs(textView.frame.height - contentHeight) > 0.5 {
            textView.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)
        }
        updateScrollerVisibility(contentHeight: contentHeight)
    }

    func updateScrollerVisibility(contentHeight: CGFloat? = nil) {
        guard let textView = scrollView.documentView as? NSTextView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        let measured = contentHeight ?? {
            layoutManager.ensureLayout(for: textContainer)
            return layoutManager.usedRect(for: textContainer).maxY
        }()
        let visibleHeight = scrollView.contentView.bounds.height
        let needsScroll = measured > visibleHeight + 2
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        _ = needsScroll
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        textView.prepareForDragOperation(sender) || super.prepareForDragOperation(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = textView.draggingUpdated(sender)
        return op == [] ? super.draggingUpdated(sender) : op
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = textView.draggingEntered(sender)
        return op == [] ? super.draggingEntered(sender) : op
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        textView.performDragOperation(sender) || super.performDragOperation(sender)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textView)
        textView.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NoteEditingNSTextView: NSTextView {
    weak var editingDelegate: NoteEditingTextViewDelegate?
    var imageDropHandler: ((Data, String?) -> Bool)?
    /// When non-empty, mouse hits in this rect pass through to the SwiftUI suggest popover above.
    var wikilinkSuggestPassthroughRect: CGRect = .zero
    var wikilinkSuggestResultCount: Int = 0
    var onWikilinkSuggestRowSelected: ((Int) -> Void)?

    /// Converts a point in the text view's coordinate space to visible (scroll-adjusted) coords
    /// used by the SwiftUI suggest popover overlay.
    private func visiblePoint(for documentPoint: NSPoint) -> NSPoint {
        var point = documentPoint
        if let scrollView = enclosingScrollView {
            point.x -= scrollView.contentView.bounds.origin.x
            point.y -= scrollView.contentView.bounds.origin.y
        }
        return point
    }

    private func wikilinkSuggestRowIndex(at visiblePoint: NSPoint) -> Int? {
        let rect = wikilinkSuggestPassthroughRect
        guard rect != .zero, rect.contains(visiblePoint) else { return nil }

        let footerHeight = WikilinkSuggestPopover.footerHeight
        let listBottom = rect.maxY - footerHeight
        guard visiblePoint.y < listBottom else { return nil }

        let relativeY = visiblePoint.y - rect.minY - 4
        guard relativeY >= 0 else { return nil }

        let index = Int(relativeY / WikilinkSuggestPopover.rowHeight)
        guard index >= 0, index < wikilinkSuggestResultCount else { return nil }
        return index
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if wikilinkSuggestPassthroughRect != .zero,
           wikilinkSuggestPassthroughRect.contains(visiblePoint(for: point)) {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let visible = visiblePoint(for: point)
        if let index = wikilinkSuggestRowIndex(at: visible) {
            onWikilinkSuggestRowSelected?(index)
            return
        }
        super.mouseDown(with: event)
    }

    static var imageDragTypes: [NSPasteboard.PasteboardType] {
        [
            .fileURL,
            .png,
            .tiff,
            NSPasteboard.PasteboardType(UTType.image.identifier),
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ]
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForImageDragTypes()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        registerForImageDragTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForImageDragTypes()
    }

    func registerForImageDragTypes() {
        registerForDraggedTypes(Self.imageDragTypes)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if canAcceptImageDrag(sender) { return true }
        return super.prepareForDragOperation(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if canAcceptImageDrag(sender) { return .copy }
        return super.draggingUpdated(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if canAcceptImageDrag(sender) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if acceptImageDrag(sender) {
            return true
        }
        if imageDropHandler != nil,
           NoteImageDropSupport.pasteboardContainsImageFile(sender.draggingPasteboard) {
            return true
        }
        return super.performDragOperation(sender)
    }

    private func canAcceptImageDrag(_ sender: NSDraggingInfo) -> Bool {
        imageDropHandler != nil && NoteImageDropSupport.imagePayload(from: sender.draggingPasteboard) != nil
    }

    @discardableResult
    private func acceptImageDrag(_ sender: NSDraggingInfo) -> Bool {
        guard let handler = imageDropHandler,
              let payload = NoteImageDropSupport.imagePayload(from: sender.draggingPasteboard) else { return false }
        return handler(payload.data, payload.name)
    }

    private func imageDataFromDrag(_ sender: NSDraggingInfo) -> (data: Data, name: String?)? {
        NoteImageDropSupport.imagePayload(from: sender.draggingPasteboard)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        var menu = super.menu(for: event) ?? NSMenu()
        NoteEditingMenuBuilder.configure(menu: &menu, target: self, action: #selector(handleMarkdownEdit(_:)))
        return menu
    }

    @objc private func handleMarkdownEdit(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = MarkdownEditAction(rawValue: raw) else { return }
        (editingDelegate as? NoteEditingNSTextViewDelegate)?.noteEditingTextView(self, apply: action)
    }
}

protocol NoteEditingNSTextViewDelegate: NoteEditingTextViewDelegate {
    func noteEditingTextView(_ textView: NoteEditingNSTextView, apply action: MarkdownEditAction)
    func noteEditingTextView(_ textView: NoteEditingNSTextView, insertSnippet snippet: String)
}

private struct NoteBodyTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var caretRect: CGRect
    @Binding var selectionRects: [CGRect]
    @Binding var suggestAnchorRect: CGRect
    var wikilinkSuggestPassthroughRect: CGRect
    var wikilinkSuggestResultCount: Int = 0
    var wikilinkInsertRevision: Int = 0
    var onSuggestRowSelect: (Int) -> Void = { _ in }
    var isFocused: FocusState<Bool>.Binding
    var fontSize: CGFloat
    var embeddedInCanvas: Bool
    var containerSize: CGSize?
    var editorBackground: Color
    var vaultURL: URL?
    var hideResolvedImageEmbeds: Bool
    var imageEmbedMaxWidth: CGFloat? = nil
    var hideTaskListMarkers: Bool = false
    var onSelectionChange: () -> Void
    var onSuggestKey: (WikilinkSuggestKey) -> Bool
    var onTextEdited: ((String, Bool) -> Void)?
    var toolbarBridge: NoteFormattingToolbarBridge? = nil
    var onImageAttachmentDrop: ((Data, String?) -> Bool)? = nil
    var layoutRefreshToken: Int = 0
    var selectionRevealToken: Int = 0
    var onContentScroll: ((CanvasNoteScrollMetrics) -> Void)? = nil

    var imageEmbedLayoutWidth: CGFloat? {
        guard hideResolvedImageEmbeds else { return nil }
        if let imageEmbedMaxWidth, imageEmbedMaxWidth > 1 { return imageEmbedMaxWidth }
        guard embeddedInCanvas, let width = containerSize?.width, width > 1 else { return nil }
        return max(1, width)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let textView = NoteEditingNSTextView()
        textView.editingDelegate = context.coordinator
        textView.imageDropHandler = onImageAttachmentDrop
        configure(textView: textView, coordinator: context.coordinator)

        if embeddedInCanvas {
            let container = CanvasNoteTextContainerView(textView: textView)
            context.coordinator.attach(textView: textView, container: container)
            context.coordinator.applyContent(text, selectedRange: selectedRange, to: textView)
            return container
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        context.coordinator.attach(textView: textView)
        context.coordinator.applyContent(text, selectedRange: selectedRange, to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let textView: NoteEditingNSTextView
        if embeddedInCanvas, let container = nsView as? CanvasNoteTextContainerView {
            textView = container.textView
        } else if let scrollView = nsView as? NSScrollView,
                  let embeddedTextView = scrollView.documentView as? NoteEditingNSTextView {
            textView = embeddedTextView
        } else {
            return
        }

        context.coordinator.parent = self
        context.coordinator.syncFontSizeIfNeeded(in: textView, container: nsView as? CanvasNoteTextContainerView)
        context.coordinator.syncIfNeeded(text: text, selectedRange: selectedRange, in: textView)
        if wikilinkInsertRevision != context.coordinator.lastWikilinkInsertRevision {
            context.coordinator.lastWikilinkInsertRevision = wikilinkInsertRevision
            if context.coordinator.isLiveEditing(in: textView) {
                context.coordinator.applyContent(text, selectedRange: selectedRange, to: textView)
                context.coordinator.syncEditingChrome(in: textView)
            }
        }
        context.coordinator.revealSelectionIfNeeded(token: selectionRevealToken, in: textView)
        context.coordinator.configureToolbarBridge(toolbarBridge)
        textView.imageDropHandler = onImageAttachmentDrop
        if onImageAttachmentDrop != nil {
            textView.registerForImageDragTypes()
        }
        if embeddedInCanvas, let container = nsView as? CanvasNoteTextContainerView {
            context.coordinator.refreshLayoutIfNeeded(
                token: layoutRefreshToken,
                in: textView,
                container: container
            )
            container.relayoutDocumentTextView()
            if let scrollView = container.scrollView as CanvasNoteScrollView? {
                context.coordinator.emitContentScroll(from: scrollView, textView: textView, deferUpdate: true)
            }
            if isFocused.wrappedValue {
                DispatchQueue.main.async {
                    container.relayoutDocumentTextView()
                }
            }
        }

        if isFocused.wrappedValue, !context.coordinator.isLiveEditing(in: textView) {
            textView.window?.makeFirstResponder(textView)
        }
        if isFocused.wrappedValue {
            context.coordinator.syncEditingChrome(in: textView)
        }
        textView.wikilinkSuggestPassthroughRect = wikilinkSuggestPassthroughRect
        textView.wikilinkSuggestResultCount = wikilinkSuggestResultCount
        textView.onWikilinkSuggestRowSelected = { index in
            context.coordinator.parent.onSuggestRowSelect(index)
        }
        context.coordinator.updateWikilinkSuggestClickMonitor(
            passthroughRect: wikilinkSuggestPassthroughRect,
            resultCount: wikilinkSuggestResultCount,
            textView: textView,
            onSelect: { index in
                context.coordinator.parent.onSuggestRowSelect(index)
            }
        )
    }

    private func configure(textView: NoteEditingNSTextView, coordinator: Coordinator) {
        textView.delegate = coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = NSColor(AppColors.textPrimary)
        if embeddedInCanvas {
            textView.textContainer?.heightTracksTextView = false
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        if embeddedInCanvas && hideResolvedImageEmbeds {
            textView.insertionPointColor = .clear
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor.clear,
            ]
        } else if hideResolvedImageEmbeds && !embeddedInCanvas {
            textView.insertionPointColor = .clear
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor.clear,
            ]
        } else {
            textView.insertionPointColor = NSColor(AppColors.textPrimary)
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.28),
            ]
        }
        textView.registerForImageDragTypes()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NoteEditingNSTextViewDelegate {
        var parent: NoteBodyTextViewRepresentable
        weak var textView: NoteEditingNSTextView?
        weak var containerView: CanvasNoteTextContainerView?
        private var isApplyingProgrammaticChange = false
        private var lastLayoutRefreshToken = -1
        private var lastSelectionRevealToken = -1
        private var lastAppliedFontSize: CGFloat = -1
        var lastWikilinkInsertRevision = -1
        private var wikilinkSuggestClickMonitor: Any?
        private var wikilinkSuggestPassthroughRect: CGRect = .zero
        private var wikilinkSuggestResultCount = 0
        private var wikilinkSuggestOnSelect: ((Int) -> Void)?
        private weak var wikilinkSuggestTextView: NSTextView?

        init(parent: NoteBodyTextViewRepresentable) {
            self.parent = parent
        }

        deinit {
            removeWikilinkSuggestClickMonitor()
        }

        func updateWikilinkSuggestClickMonitor(
            passthroughRect: CGRect,
            resultCount: Int,
            textView: NSTextView,
            onSelect: @escaping (Int) -> Void
        ) {
            wikilinkSuggestPassthroughRect = passthroughRect
            wikilinkSuggestResultCount = resultCount
            wikilinkSuggestOnSelect = onSelect
            wikilinkSuggestTextView = textView

            guard passthroughRect != .zero, resultCount > 0 else {
                removeWikilinkSuggestClickMonitor()
                return
            }

            guard wikilinkSuggestClickMonitor == nil else { return }

            wikilinkSuggestClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                return self.handleWikilinkSuggestClick(event) ?? event
            }
        }

        private func handleWikilinkSuggestClick(_ event: NSEvent) -> NSEvent? {
            guard let textView = wikilinkSuggestTextView,
                  let window = textView.window,
                  event.window === window,
                  wikilinkSuggestPassthroughRect != .zero else {
                return nil
            }

            let visible = Self.wikilinkSuggestVisiblePoint(
                in: textView,
                documentPoint: textView.convert(event.locationInWindow, from: nil)
            )
            guard let index = Self.wikilinkSuggestRowIndex(
                at: visible,
                in: wikilinkSuggestPassthroughRect,
                resultCount: wikilinkSuggestResultCount
            ) else {
                return nil
            }

            wikilinkSuggestOnSelect?(index)
            return nil
        }

        private func removeWikilinkSuggestClickMonitor() {
            if let wikilinkSuggestClickMonitor {
                NSEvent.removeMonitor(wikilinkSuggestClickMonitor)
                self.wikilinkSuggestClickMonitor = nil
            }
        }

        private static func wikilinkSuggestVisiblePoint(in textView: NSTextView, documentPoint: NSPoint) -> NSPoint {
            var point = documentPoint
            if let scrollView = textView.enclosingScrollView {
                point.x -= scrollView.contentView.bounds.origin.x
                point.y -= scrollView.contentView.bounds.origin.y
            }
            return point
        }

        private static func wikilinkSuggestRowIndex(
            at visiblePoint: NSPoint,
            in passthroughRect: CGRect,
            resultCount: Int
        ) -> Int? {
            guard passthroughRect.contains(visiblePoint) else { return nil }

            let listBottom = passthroughRect.maxY - WikilinkSuggestPopover.footerHeight
            guard visiblePoint.y < listBottom else { return nil }

            let relativeY = visiblePoint.y - passthroughRect.minY - 4
            guard relativeY >= 0 else { return nil }

            let index = Int(relativeY / WikilinkSuggestPopover.rowHeight)
            guard index >= 0, index < resultCount else { return nil }
            return index
        }

        func syncFontSizeIfNeeded(in textView: NSTextView, container: CanvasNoteTextContainerView? = nil) {
            guard abs(parent.fontSize - lastAppliedFontSize) > 0.01 else { return }
            lastAppliedFontSize = parent.fontSize
            textView.font = .systemFont(ofSize: parent.fontSize)
            if NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            ) || NoteTextEditingCoordinatorSupport.usesWysiwygEditing(
                embeddedInCanvas: parent.embeddedInCanvas,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            ) {
                applyContent(parent.text, selectedRange: parent.selectedRange, to: textView)
            } else {
                restyle(textView)
            }
            container?.relayoutDocumentTextView()
        }

        func attach(textView: NoteEditingNSTextView, container: CanvasNoteTextContainerView? = nil) {
            self.textView = textView
            self.containerView = container
            container?.onScroll = { [weak self] in
                guard let self, let textView = self.textView else { return }
                if let scrollView = self.containerView?.scrollView {
                    self.emitContentScroll(from: scrollView, textView: textView)
                }
                self.updateCaretRect(for: textView)
            }
            if parent.embeddedInCanvas {
                CanvasNoteCardScrollBridge.register(owner: "edit") { [weak self] delta in
                    guard let self, let scrollView = self.containerView?.scrollView,
                          let textView = self.textView else { return .none }
                    let result = CanvasNoteCardScrollBridge.scroll(scrollView, by: delta)
                    self.emitContentScroll(from: scrollView, textView: textView)
                    self.updateCaretRect(for: textView)
                    return result
                }
                DispatchQueue.main.async { [weak textView] in
                    guard let textView, textView.window != nil else { return }
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }

        func configureToolbarBridge(_ bridge: NoteFormattingToolbarBridge?) {
            guard let textView else { return }
            Task { @MainActor in
                bridge?.textView = textView
                bridge?.insertSnippetHandler = { [weak self] snippet in
                    guard let self, let textView = self.textView else { return }
                    self.noteEditingTextView(textView, insertSnippet: snippet)
                }
            }
        }

        private enum CanvasEmbedNavKey {
            case enter
            case down
        }

        private func handleCanvasEmbedNavigation(in textView: NSTextView, key: CanvasEmbedNavKey) -> Bool {
            guard parent.embeddedInCanvas, parent.hideResolvedImageEmbeds else { return false }

            let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )

            let source: String
            let selected: NSRange
            if usesAttachments {
                source = NoteImageEmbedAttributedSupport.markdown(
                    from: textView.attributedString(),
                    vaultURL: parent.vaultURL
                )
                selected = NoteImageEmbedAttributedSupport.markdownRange(
                    fromAttributedRange: textView.selectedRange(),
                    in: source,
                    vaultURL: parent.vaultURL
                )
            } else {
                source = textView.string
                selected = textView.selectedRange()
            }

            switch key {
            case .enter:
                guard let result = NoteCardEmbedEditingSupport.newlineBelowImageEmbed(
                    in: source,
                    selectedRange: selected,
                    vaultURL: parent.vaultURL
                ) else { return false }
                applyCanvasNavigation(result, to: textView)
                return true
            case .down:
                guard let markdownTarget = NoteCardEmbedEditingSupport.moveDownPastImageEmbed(
                    in: source,
                    selectedRange: selected,
                    vaultURL: parent.vaultURL
                ) else { return false }
                let target = usesAttachments
                    ? NoteImageEmbedAttributedSupport.attributedRange(
                        fromMarkdownRange: markdownTarget,
                        in: source,
                        vaultURL: parent.vaultURL
                    )
                    : markdownTarget
                textView.setSelectedRange(target)
                updateCaretRect(for: textView)
                parent.onSelectionChange()
                return true
            }
        }

        private func applyCanvasNavigation(
            _ result: (text: String, selectedRange: NSRange),
            to textView: NSTextView
        ) {
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.applyEditedText(
                result,
                textView: textView,
                embeddedInCanvas: parent.embeddedInCanvas,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            Task { @MainActor in
                parent.text = updates.text
                parent.selectedRange = updates.selectedRange
                updateCaretRect(for: textView)
                parent.onSelectionChange()
                parent.onTextEdited?(updates.text, false)
                isApplyingProgrammaticChange = false
            }
        }

        func noteEditingTextView(_ textView: NoteEditingNSTextView, apply action: MarkdownEditAction) {
            if action == .attachment {
                Task { @MainActor in
                    parent.toolbarBridge?.requestAttachment()
                }
                return
            }
            guard let textView = self.textView else { return }
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.applyMarkdownEdit(
                action,
                textView: textView,
                markdownBinding: parent.text,
                embeddedInCanvas: parent.embeddedInCanvas,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            Task { @MainActor in
                parent.text = updates.text
                parent.selectedRange = updates.selectedRange
                updateCaretRect(for: textView)
                parent.onSelectionChange()
                parent.onTextEdited?(updates.text, false)
                isApplyingProgrammaticChange = false
            }
        }

        func noteEditingTextView(_ textView: NoteEditingNSTextView, insertSnippet snippet: String) {
            guard let textView = self.textView else { return }
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.insertSnippet(
                snippet,
                textView: textView,
                markdownBinding: parent.text,
                embeddedInCanvas: parent.embeddedInCanvas,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            Task { @MainActor in
                parent.text = updates.text
                parent.selectedRange = updates.selectedRange
                updateCaretRect(for: textView)
                parent.onSelectionChange()
                parent.onTextEdited?(updates.text, false)
                isApplyingProgrammaticChange = false
            }
        }

        func noteTextViewDidApplyEdit(_ textView: AnyObject) {}

        func isLiveEditing(in textView: NSTextView) -> Bool {
            guard let window = textView.window else { return false }
            if window.firstResponder === textView { return true }
            if let fieldEditor = window.fieldEditor(false, for: textView) as AnyObject?,
               window.firstResponder === fieldEditor {
                return true
            }
            return false
        }

        func syncIfNeeded(text: String, selectedRange: NSRange, in textView: NSTextView) {
            guard !isApplyingProgrammaticChange else { return }

            let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )

            if usesAttachments, isLiveEditing(in: textView) {
                return
            }

            if isLiveEditing(in: textView), textView.string != text {
                return
            }

            if usesAttachments {
                if NoteImageEmbedAttributedSupport.shouldRebuildAttributedText(
                    bindingMarkdown: text,
                    currentAttributed: textView.attributedString(),
                    vaultURL: parent.vaultURL
                ) {
                    applyContent(text, selectedRange: selectedRange, to: textView)
                } else if !isLiveEditing(in: textView) {
                    let expected = NoteImageEmbedAttributedSupport.attributedRange(
                        fromMarkdownRange: selectedRange,
                        in: text,
                        vaultURL: parent.vaultURL
                    )
                    if textView.selectedRange() != expected {
                        textView.setSelectedRange(expected)
                    }
                }
                return
            }

            if textView.string != text {
                applyContent(text, selectedRange: selectedRange, to: textView)
            } else if !isLiveEditing(in: textView), textView.selectedRange() != selectedRange {
                textView.setSelectedRange(selectedRange)
                restyle(textView)
            }
        }

        func applyContent(_ content: String, selectedRange: NSRange, to textView: NSTextView) {
            isApplyingProgrammaticChange = true
            defer { isApplyingProgrammaticChange = false }

            let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )

            NoteUndoRegistration.perform(on: textView.undoManager) {
                let styled = NoteTextEditingCoordinatorSupport.styledContent(
                    content,
                    selectedRange: selectedRange,
                    fontSize: parent.fontSize,
                    editorBackground: parent.editorBackground,
                    vaultURL: parent.vaultURL,
                    hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                    hideTaskListMarkers: parent.hideTaskListMarkers,
                    embeddedInCanvas: parent.embeddedInCanvas
                )
                textView.textStorage?.setAttributedString(styled)
                if usesAttachments {
                    textView.setSelectedRange(
                        NoteImageEmbedAttributedSupport.attributedRange(
                            fromMarkdownRange: selectedRange,
                            in: content,
                            vaultURL: parent.vaultURL
                        )
                    )
                } else if NoteTextEditingCoordinatorSupport.usesWysiwygEditing(
                    embeddedInCanvas: parent.embeddedInCanvas,
                    hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                    vaultURL: parent.vaultURL,
                    imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
                ) {
                    textView.setSelectedRange(
                        MarkdownWysiwygEditingSupport.displayRange(
                            fromMarkdown: selectedRange,
                            in: content,
                            fontSize: parent.fontSize,
                            editorBackground: parent.editorBackground,
                            hideTaskListMarkers: parent.hideTaskListMarkers
                        )
                    )
                } else {
                    textView.setSelectedRange(clampedRange(selectedRange, in: content))
                }
            }
            updateCaretRect(for: textView)
            containerView?.relayoutDocumentTextView()
            if let scrollView = containerView?.scrollView {
                emitContentScroll(from: scrollView, textView: textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingProgrammaticChange else { return }

            let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )

            var newText: String
            var newRange: NSRange

            if usesAttachments {
                newText = NoteImageEmbedAttributedSupport.markdownPreservingEmbeds(
                    from: textView.attributedString(),
                    previousMarkdown: parent.text,
                    vaultURL: parent.vaultURL
                )
                newRange = NoteImageEmbedAttributedSupport.markdownRange(
                    fromAttributedRange: textView.selectedRange(),
                    in: newText,
                    vaultURL: parent.vaultURL
                )
            } else {
                restyle(textView)
                newText = textView.string
                newRange = textView.selectedRange()
                if parent.embeddedInCanvas, parent.hideResolvedImageEmbeds {
                    let sanitized = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(
                        in: newText,
                        vaultURL: parent.vaultURL,
                        selectedRange: newRange
                    )
                    if sanitized.text != newText {
                        isApplyingProgrammaticChange = true
                        NoteUndoRegistration.perform(on: textView.undoManager) {
                            let styled = WikilinkEditorSupport.attributedString(
                                for: sanitized.text,
                                selectedRange: sanitized.selectedRange ?? newRange,
                                fontSize: parent.fontSize,
                                hiddenDelimiterOn: parent.editorBackground,
                                vaultURL: parent.vaultURL,
                                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
                            )
                            textView.textStorage?.setAttributedString(styled)
                            textView.setSelectedRange(sanitized.selectedRange ?? newRange)
                        }
                        isApplyingProgrammaticChange = false
                        newText = sanitized.text
                        newRange = sanitized.selectedRange ?? newRange
                    }
                }
            }

            let fromTextUndo = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
            parent.text = newText
            parent.selectedRange = newRange
            updateCaretRect(for: textView)
            Task { @MainActor in
                scrollCaretIntoView(textView)
                containerView?.relayoutDocumentTextView()
                if let scrollView = containerView?.scrollView {
                    emitContentScroll(from: scrollView, textView: textView)
                }
                updateCaretRect(for: textView)
                parent.onSelectionChange()
                parent.onTextEdited?(newText, fromTextUndo)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingProgrammaticChange else { return }
            let newRange = NoteTextEditingCoordinatorSupport.markdownBindingRange(
                fromAttributedRange: textView.selectedRange(),
                markdown: parent.text,
                embeddedInCanvas: parent.embeddedInCanvas,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            if !NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            ) {
                restyle(textView)
            }
            parent.selectedRange = newRange
            updateCaretRect(for: textView)
            Task { @MainActor in
                scrollCaretIntoView(textView)
                parent.onSelectionChange()
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                return parent.onSuggestKey(.up)
            case #selector(NSResponder.moveDown(_:)):
                if handleCanvasEmbedNavigation(in: textView, key: .down) { return true }
                return parent.onSuggestKey(.down)
            case #selector(NSResponder.insertNewline(_:)):
                if handleCanvasEmbedNavigation(in: textView, key: .enter) { return true }
                return parent.onSuggestKey(.enter)
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onSuggestKey(.escape)
            default:
                return false
            }
        }

        private func restyle(_ textView: NSTextView) {
            NoteTextEditingCoordinatorSupport.restyleInPlace(
                textView: textView,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
        }

        func restyleForLayoutRefresh(in textView: NSTextView) {
            restyle(textView)
            containerView?.relayoutDocumentTextView()
        }

        func refreshLayoutIfNeeded(
            token: Int,
            in textView: NSTextView,
            container: CanvasNoteTextContainerView? = nil
        ) {
            guard token != lastLayoutRefreshToken else { return }
            lastLayoutRefreshToken = token
            if NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            ) {
                if isLiveEditing(in: textView) {
                    container?.relayoutDocumentTextView()
                    if let scrollView = containerView?.scrollView {
                        emitContentScroll(from: scrollView, textView: textView)
                    }
                    return
                }
                applyContent(parent.text, selectedRange: parent.selectedRange, to: textView)
            } else {
                restyle(textView)
            }
            container?.relayoutDocumentTextView()
            if let scrollView = containerView?.scrollView {
                emitContentScroll(from: scrollView, textView: textView)
            }
        }

        func revealSelectionIfNeeded(token: Int, in textView: NSTextView) {
            guard token != lastSelectionRevealToken else { return }
            lastSelectionRevealToken = token
            scrollCaretIntoView(textView)
        }

        func emitContentScroll(from scrollView: NSScrollView, textView: NSTextView, deferUpdate: Bool = false) {
            guard let handler = parent.onContentScroll else { return }
            let metrics = CanvasNoteScrollMetrics(
                offset: scrollView.contentView.bounds.origin,
                contentHeight: textView.frame.height,
                viewportHeight: scrollView.contentView.bounds.height
            )
            if deferUpdate {
                Task { @MainActor in
                    handler(metrics)
                }
            } else {
                handler(metrics)
            }
        }

        private func updateEditingChrome(for textView: NSTextView) {
            let rect = NoteEditingChromeSupport.caretRect(in: textView, fontSize: parent.fontSize)
            let shouldTrackSelection = parent.embeddedInCanvas
                || (parent.hideResolvedImageEmbeds && !parent.embeddedInCanvas)
            Task { @MainActor in
                parent.caretRect = rect
                if shouldTrackSelection {
                    parent.selectionRects = NoteEditingChromeSupport.selectionRects(in: textView)
                }
                updateSuggestAnchor(in: textView)
            }
        }

        private func updateSuggestAnchor(in textView: NSTextView) {
            let cursor = parent.selectedRange.location + parent.selectedRange.length
            guard let query = WikilinkEditorSupport.activeQuery(in: parent.text, cursor: cursor) else {
                parent.suggestAnchorRect = .zero
                return
            }
            let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )
            let anchorIndex = usesAttachments
                ? NoteImageEmbedAttributedSupport.attributedRange(
                    fromMarkdownRange: NSRange(location: query.replaceRange.location, length: 0),
                    in: parent.text,
                    vaultURL: parent.vaultURL
                ).location
                : query.replaceRange.location
            parent.suggestAnchorRect = NoteEditingChromeSupport.wikilinkSuggestAnchor(
                in: textView,
                characterIndex: anchorIndex,
                fontSize: parent.fontSize
            )
        }

        private func updateCaretRect(for textView: NSTextView) {
            updateEditingChrome(for: textView)
        }

        func syncEditingChrome(in textView: NSTextView) {
            updateEditingChrome(for: textView)
        }

        func scrollCaretIntoView(_ textView: NSTextView) {
            textView.scrollRangeToVisible(textView.selectedRange())
            updateCaretRect(for: textView)
        }

        private func clampedRange(_ range: NSRange, in content: String) -> NSRange {
            let length = (content as NSString).length
            let location = min(max(range.location, 0), length)
            let upper = min(range.location + range.length, length)
            return NSRange(location: location, length: max(0, upper - location))
        }
    }
}

#else

final class CanvasNoteIOSScrollView: UIScrollView {
    var onScroll: (() -> Void)?

    override var contentOffset: CGPoint {
        didSet {
            if contentOffset != oldValue {
                onScroll?()
            }
        }
    }
}

/// Mirrors the Mac `CanvasNoteTextContainerView` — outer UIScrollView + fixed-width UITextView document.
final class CanvasNoteUITextContainerView: UIView, UIGestureRecognizerDelegate {
    let scrollView: CanvasNoteIOSScrollView
    let textView: NoteEditingUITextView
    private var panOriginOffsetY: CGFloat = 0
    private lazy var scrollPanGesture: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        return pan
    }()

    var onScroll: (() -> Void)? {
        get { scrollView.onScroll }
        set { scrollView.onScroll = newValue }
    }

    init(textView: NoteEditingUITextView) {
        self.textView = textView
        self.scrollView = CanvasNoteIOSScrollView()
        super.init(frame: .zero)
        backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = false
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.heightTracksTextView = false
        scrollView.addSubview(textView)
        addSubview(scrollView)
        addGestureRecognizer(scrollPanGesture)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        relayoutDocumentTextView()
    }

    func relayoutDocumentTextView() {
        guard scrollView.bounds.width > 1, scrollView.bounds.height > 1 else { return }

        let textContainer = textView.textContainer
        let layoutManager = textView.layoutManager
        let width = max(1, scrollView.bounds.width)
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)

        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let inset = textView.textContainerInset
        let textHeight = ceil(used.maxY + inset.top + inset.bottom)
        let contentHeight = textHeight
        let newFrame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
        if textView.frame != newFrame {
            textView.frame = newFrame
        }
        let newContentSize = CGSize(width: width, height: contentHeight)
        if scrollView.contentSize != newContentSize {
            scrollView.contentSize = newContentSize
        }
    }

    func resetScrollToTop() {
        scrollView.setContentOffset(.zero, animated: false)
        panOriginOffsetY = 0
    }

    @objc private func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
        let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        guard maxOffset > 0.5 else { return }

        switch gesture.state {
        case .began:
            panOriginOffsetY = scrollView.contentOffset.y
        case .changed:
            let proposed = panOriginOffsetY - gesture.translation(in: scrollView).y
            scrollView.contentOffset.y = min(max(0, proposed), maxOffset)
        case .ended, .cancelled, .failed:
            panOriginOffsetY = scrollView.contentOffset.y
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === scrollPanGesture else { return true }
        return scrollView.contentSize.height > scrollView.bounds.height + 0.5
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === scrollPanGesture
    }
}

final class NoteEditingUITextView: UITextView {
    weak var editingDelegate: NoteEditingTextViewDelegate?
    var toolbarBridge: NoteFormattingToolbarBridge?
    weak var dropDelegate: UIDropInteractionDelegate?
    var imageDropHandler: ((Data, String?) -> Bool)?
    var onScroll: (() -> Void)?
    var canvasMinimalScrolling = false
    var suggestKeyHandler: ((WikilinkSuggestKey) -> Bool)?

    override var keyCommands: [UIKeyCommand]? {
        guard suggestKeyHandler != nil else { return super.keyCommands }
        let commands = [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleSuggestUpKey)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleSuggestDownKey)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleSuggestEscapeKey)),
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands + (super.keyCommands ?? [])
    }

    @objc private func handleSuggestUpKey() {
        _ = suggestKeyHandler?(.up)
    }

    @objc private func handleSuggestDownKey() {
        _ = suggestKeyHandler?(.down)
    }

    @objc private func handleSuggestEscapeKey() {
        _ = suggestKeyHandler?(.escape)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        guard !canvasMinimalScrolling else { return }
        super.scrollRangeToVisible(range)
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(contentOffset, animated: animated)
        onScroll?()
    }

    func refreshDropInteraction() {
        interactions.filter { $0 is UIDropInteraction }.forEach { removeInteraction($0) }
        guard imageDropHandler != nil, let dropDelegate else { return }
        addInteraction(UIDropInteraction(delegate: dropDelegate))
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configureToolbarBridge(_ bridge: NoteFormattingToolbarBridge?) {
        if toolbarBridge === bridge, bridge?.textView === self {
            bridge?.attachInputAccessory(to: self)
            return
        }
        toolbarBridge = bridge
        bridge?.textView = self
        bridge?.applyAction = { [weak self] action in
            guard let self else { return }
            if action == .attachment {
                self.toolbarBridge?.requestAttachment()
                return
            }
            (self.editingDelegate as? NoteEditingUITextViewDelegate)?
                .noteEditingTextView(self, apply: action)
        }
        bridge?.insertSnippetHandler = { [weak self] snippet in
            guard let self else { return }
            (self.editingDelegate as? NoteEditingUITextViewDelegate)?
                .noteEditingTextView(self, insertSnippet: snippet)
        }
        if let bridge {
            bridge.attachInputAccessory(to: self)
        } else if inputAccessoryView != nil {
            inputAccessoryView = nil
            if isFirstResponder {
                reloadInputViews()
            }
        }
    }

    func refreshFormattingToolbar() {
        toolbarBridge?.scheduleRefresh()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, let toolbarBridge {
            toolbarBridge.attachInputAccessory(to: self)
            refreshFormattingToolbar()
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            refreshFormattingToolbar()
        }
        return resigned
    }

    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        var actions = suggestedActions
        let customMenus = NoteEditingMenuBuilder.editingMenus { [weak self] action in
            guard let self else { return }
            (self.editingDelegate as? NoteEditingUITextViewDelegate)?.noteEditingTextView(self, apply: action)
        }
        actions.insert(contentsOf: customMenus, at: 0)
        return UIMenu(children: actions)
    }
}

protocol NoteEditingUITextViewDelegate: NoteEditingTextViewDelegate {
    func noteEditingTextView(_ textView: NoteEditingUITextView, apply action: MarkdownEditAction)
    func noteEditingTextView(_ textView: NoteEditingUITextView, insertSnippet snippet: String)
}

private struct NoteBodyTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var caretRect: CGRect
    @Binding var selectionRects: [CGRect]
    @Binding var suggestAnchorRect: CGRect
    var wikilinkInsertRevision: Int = 0
    var isFocused: FocusState<Bool>.Binding
    var fontSize: CGFloat
    var embeddedInCanvas: Bool
    var containerSize: CGSize?
    var editorBackground: Color
    var vaultURL: URL?
    var hideResolvedImageEmbeds: Bool
    var imageEmbedMaxWidth: CGFloat? = nil
    var hideTaskListMarkers: Bool
    var onSelectionChange: () -> Void
    var onSuggestKey: (WikilinkSuggestKey) -> Bool
    var onTextEdited: ((String, Bool) -> Void)?
    var toolbarBridge: NoteFormattingToolbarBridge? = nil
    var onImageAttachmentDrop: ((Data, String?) -> Bool)? = nil
    var layoutRefreshToken: Int = 0
    var selectionRevealToken: Int = 0
    var onContentScroll: ((CanvasNoteScrollMetrics) -> Void)? = nil
    var fillsAvailableHeight: Bool = false
    @Binding var keyboardBottomOverlap: CGFloat

    var imageEmbedLayoutWidth: CGFloat? {
        guard hideResolvedImageEmbeds else { return nil }
        if let imageEmbedMaxWidth, imageEmbedMaxWidth > 1 { return imageEmbedMaxWidth }
        if fillsAvailableHeight, let width = containerSize?.width, width > 1 { return max(1, width) }
        guard embeddedInCanvas, let width = containerSize?.width, width > 1 else { return nil }
        return max(1, width)
    }

    var showsCustomEditingChrome: Bool {
        hideResolvedImageEmbeds
    }

    var hidesNativeInsertionPoint: Bool {
        hideResolvedImageEmbeds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let textView = makeConfiguredTextView(context: context)
        if embeddedInCanvas {
            let container = CanvasNoteUITextContainerView(textView: textView)
            context.coordinator.attach(textView: textView, container: container)
            context.coordinator.applyContent(text, selectedRange: selectedRange, to: textView)
            container.relayoutDocumentTextView()
            container.resetScrollToTop()
            context.coordinator.emitContentScroll(from: container.scrollView, deferUpdate: true)
            return container
        }

        context.coordinator.attach(textView: textView)
        context.coordinator.applyContent(text, selectedRange: selectedRange, to: textView)
        if fillsAvailableHeight, let containerSize, containerSize.height > 0 {
            textView.frame = CGRect(origin: .zero, size: containerSize)
        }
        return textView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let textView: NoteEditingUITextView
        let container: CanvasNoteUITextContainerView?
        if let embeddedContainer = uiView as? CanvasNoteUITextContainerView {
            textView = embeddedContainer.textView
            container = embeddedContainer
        } else if let standaloneTextView = uiView as? NoteEditingUITextView {
            textView = standaloneTextView
            container = nil
        } else {
            return
        }

        context.coordinator.parent = self
        context.coordinator.syncFontSizeIfNeeded(in: textView, container: container)
        textView.editingDelegate = context.coordinator
        textView.configureToolbarBridge(toolbarBridge)
        textView.imageDropHandler = onImageAttachmentDrop
        textView.refreshDropInteraction()
        context.coordinator.syncIfNeeded(text: text, selectedRange: selectedRange, in: textView)
        if wikilinkInsertRevision != context.coordinator.lastWikilinkInsertRevision {
            context.coordinator.lastWikilinkInsertRevision = wikilinkInsertRevision
            if context.coordinator.isLiveEditing(in: textView) {
                context.coordinator.applyContent(text, selectedRange: selectedRange, to: textView)
                context.coordinator.syncEditingChrome(in: textView)
            }
        }
        context.coordinator.revealSelectionIfNeeded(token: selectionRevealToken, in: textView)
        container?.relayoutDocumentTextView()
        context.coordinator.refreshLayoutIfNeeded(
            token: layoutRefreshToken,
            in: textView,
            container: container
        )
        if isFocused.wrappedValue, !textView.isFirstResponder {
            _ = textView.becomeFirstResponder()
        }
        if let scrollView = container?.scrollView {
            context.coordinator.emitContentScroll(from: scrollView, deferUpdate: true)
        }
        if hidesNativeInsertionPoint {
            textView.tintColor = .clear
        } else {
            #if os(iOS)
            textView.tintColor = .systemBlue
            #endif
        }
        if isFocused.wrappedValue {
            Task { @MainActor in
                context.coordinator.syncEditingChrome(in: textView)
            }
        }
        textView.suggestKeyHandler = { key in
            context.coordinator.parent.onSuggestKey(key)
        }

        if fillsAvailableHeight, let containerSize, containerSize.height > 0, container == nil {
            textView.frame = CGRect(origin: .zero, size: containerSize)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        guard embeddedInCanvas,
              let containerSize,
              containerSize.width > 1,
              containerSize.height > 1 else { return nil }
        return containerSize
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detachKeyboardObserver()
    }

    private func makeConfiguredTextView(context: Context) -> NoteEditingUITextView {
        let textView = NoteEditingUITextView()
        textView.editingDelegate = context.coordinator
        textView.delegate = context.coordinator
        textView.dropDelegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = UIColor(AppColors.textPrimary)
        textView.isScrollEnabled = embeddedInCanvas ? false : true
        textView.contentInsetAdjustmentBehavior = .never
        textView.showsVerticalScrollIndicator = fillsAvailableHeight || !embeddedInCanvas
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.canvasMinimalScrolling = embeddedInCanvas
        if hidesNativeInsertionPoint {
            textView.tintColor = .clear
        } else {
            #if os(iOS)
            textView.tintColor = .systemBlue
            #endif
        }
        textView.imageDropHandler = onImageAttachmentDrop
        textView.refreshDropInteraction()
        textView.configureToolbarBridge(toolbarBridge)
        return textView
    }

    final class Coordinator: NSObject, UITextViewDelegate, NoteEditingUITextViewDelegate, UIDropInteractionDelegate {
        var parent: NoteBodyTextViewRepresentable
        weak var textView: NoteEditingUITextView?
        weak var containerView: CanvasNoteUITextContainerView?
        private var isApplyingProgrammaticChange = false
        private var lastLayoutRefreshToken = -1
        private var lastSelectionRevealToken = -1
        var lastWikilinkInsertRevision = -1
        private var lastAppliedFontSize: CGFloat = -1
        private let standaloneKeyboardObserver = NoteStandaloneEditorKeyboardObserver()

        init(parent: NoteBodyTextViewRepresentable) {
            self.parent = parent
        }

        func syncFontSizeIfNeeded(in textView: UITextView, container: CanvasNoteUITextContainerView? = nil) {
            guard abs(parent.fontSize - lastAppliedFontSize) > 0.01 else { return }
            lastAppliedFontSize = parent.fontSize
            textView.font = .systemFont(ofSize: parent.fontSize)
            if NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            ) || NoteTextEditingCoordinatorSupport.usesWysiwygEditing(
                embeddedInCanvas: parent.embeddedInCanvas,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            ) {
                applyContent(parent.text, selectedRange: parent.selectedRange, to: textView)
            } else {
                restyle(textView)
            }
            container?.relayoutDocumentTextView()
        }

        func attach(textView: NoteEditingUITextView, container: CanvasNoteUITextContainerView? = nil) {
            self.textView = textView
            self.containerView = container
            textView.suggestKeyHandler = { [weak self] key in
                self?.parent.onSuggestKey(key) ?? false
            }
            if let container {
                container.onScroll = { [weak self] in
                    guard let self, let scrollView = self.containerView?.scrollView else { return }
                    self.emitContentScroll(from: scrollView, deferUpdate: true)
                    self.updateCaretRect(for: textView)
                }
            } else {
                textView.onScroll = { [weak self] in
                    guard let self, let textView = self.textView else { return }
                    self.emitContentScroll(from: textView, deferUpdate: true)
                    self.updateCaretRect(for: textView)
                }
                if parent.fillsAvailableHeight {
                    standaloneKeyboardObserver.attach(
                        to: textView,
                        fontSize: parent.fontSize,
                        onOverlapChange: { [weak self] overlap in
                            Task { @MainActor in
                                self?.parent.keyboardBottomOverlap = overlap
                            }
                        }
                    )
                }
            }
            if parent.embeddedInCanvas {
                CanvasNoteCardScrollBridge.register(owner: "edit") { [weak self] delta in
                    guard let self else { return .none }
                    if let scrollView = self.containerView?.scrollView {
                        let result = CanvasNoteCardScrollBridge.scroll(scrollView, by: delta)
                        self.emitContentScroll(from: scrollView, deferUpdate: true)
                        if let textView = self.textView {
                            self.updateCaretRect(for: textView)
                        }
                        return result
                    }
                    guard let textView = self.textView else { return .none }
                    let result = CanvasNoteCardScrollBridge.scroll(textView, by: delta)
                    self.emitContentScroll(from: textView, deferUpdate: true)
                    self.updateCaretRect(for: textView)
                    return result
                }
            }
        }

        private func contentScrollOffset(for textView: UITextView) -> CGPoint {
            containerView?.scrollView.contentOffset ?? textView.contentOffset
        }

        func emitContentScroll(from scrollView: UIScrollView, deferUpdate: Bool = false) {
            guard let handler = parent.onContentScroll else { return }
            let metrics = CanvasNoteScrollMetrics(
                offset: scrollView.contentOffset,
                contentHeight: scrollView.contentSize.height,
                viewportHeight: scrollView.bounds.height
            )
            if deferUpdate {
                Task { @MainActor in
                    handler(metrics)
                }
            } else {
                handler(metrics)
            }
        }

        func emitContentScroll(from textView: UITextView, deferUpdate: Bool = false) {
            emitContentScroll(from: textView as UIScrollView, deferUpdate: deferUpdate)
        }

        func noteEditingTextView(_ textView: NoteEditingUITextView, apply action: MarkdownEditAction) {
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.applyMarkdownEdit(
                action,
                textView: textView,
                markdownBinding: parent.text,
                embeddedInCanvas: parent.embeddedInCanvas,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            if !usesWysiwygEditing {
                restyle(textView)
            }
            textView.refreshFormattingToolbar()
            parent.text = updates.text
            parent.selectedRange = updates.selectedRange
            updateCaretRect(for: textView)
            parent.onSelectionChange()
            parent.onTextEdited?(updates.text, false)
            isApplyingProgrammaticChange = false
        }

        func noteEditingTextView(_ textView: NoteEditingUITextView, insertSnippet snippet: String) {
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.insertSnippet(
                snippet,
                textView: textView,
                markdownBinding: parent.text,
                embeddedInCanvas: parent.embeddedInCanvas,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            if !usesWysiwygEditing {
                restyle(textView)
            }
            textView.refreshFormattingToolbar()
            parent.text = updates.text
            parent.selectedRange = updates.selectedRange
            updateCaretRect(for: textView)
            parent.onSelectionChange()
            parent.onTextEdited?(updates.text, false)
            isApplyingProgrammaticChange = false
        }

        func noteTextViewDidApplyEdit(_ textView: AnyObject) {}

        func detachKeyboardObserver() {
            standaloneKeyboardObserver.detach()
            textView?.suggestKeyHandler = nil
        }

        private var usesWysiwygEditing: Bool {
            NoteTextEditingCoordinatorSupport.usesWysiwygEditing(
                embeddedInCanvas: parent.embeddedInCanvas,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard !isApplyingProgrammaticChange else { return true }

            if text == "\n", parent.onSuggestKey(.enter) {
                return false
            }

            if usesWysiwygEditing {
                if text == "\n" {
                    applyWysiwygNewline(at: range, to: textView)
                } else {
                    applyWysiwygTextReplacement(range: range, replacement: text, to: textView)
                }
                return false
            }

            guard text == "\n" else { return true }

            let source = textView.text ?? ""

            if parent.embeddedInCanvas,
               parent.hideResolvedImageEmbeds,
               let result = NoteCardEmbedEditingSupport.newlineBelowImageEmbed(
                   in: source,
                   selectedRange: range,
                   vaultURL: parent.vaultURL
               ) {
                applyProgrammaticNewline(result, to: textView)
                return false
            }

            let result = MarkdownEditingSupport.newlineInDocument(in: source, selectedRange: range)
            applyProgrammaticNewline(result, to: textView)
            return false
        }

        private func applyWysiwygTextReplacement(range: NSRange, replacement: String, to textView: UITextView) {
            let markdown = parent.text
            let markdownRange = MarkdownWysiwygEditingSupport.markdownRange(
                fromDisplay: range,
                in: markdown,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            let ns = markdown as NSString
            let newText = ns.replacingCharacters(in: markdownRange, with: replacement)
            let newSelection = NSRange(
                location: markdownRange.location + (replacement as NSString).length,
                length: 0
            )
            commitWysiwygEdit((newText, newSelection), to: textView)
        }

        private func applyWysiwygNewline(at range: NSRange, to textView: UITextView) {
            let markdown = parent.text
            let markdownRange = MarkdownWysiwygEditingSupport.markdownRange(
                fromDisplay: range,
                in: markdown,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            let result = MarkdownEditingSupport.newlineInDocument(in: markdown, selectedRange: markdownRange)
            commitWysiwygEdit(result, to: textView)
        }

        private func commitWysiwygEdit(
            _ result: (text: String, selectedRange: NSRange),
            to textView: UITextView
        ) {
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.applyEditedText(
                result,
                textView: textView,
                embeddedInCanvas: parent.embeddedInCanvas,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            (textView as? NoteEditingUITextView)?.refreshFormattingToolbar()
            parent.text = updates.text
            parent.selectedRange = updates.selectedRange
            updateCaretRect(for: textView)
            if parent.fillsAvailableHeight {
                scrollEmbeddedCaretIntoViewIfNeeded(for: textView)
            }
            parent.onSelectionChange()
            parent.onTextEdited?(updates.text, false)
            isApplyingProgrammaticChange = false
        }

        private func applyProgrammaticNewline(
            _ result: (text: String, selectedRange: NSRange),
            to textView: UITextView
        ) {
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.applyEditedText(
                result,
                textView: textView,
                embeddedInCanvas: parent.embeddedInCanvas,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            (textView as? NoteEditingUITextView)?.refreshFormattingToolbar()
            Task { @MainActor in
                parent.text = updates.text
                parent.selectedRange = updates.selectedRange
                updateCaretRect(for: textView)
                if parent.embeddedInCanvas {
                    relayoutEmbeddedCanvas(in: textView)
                }
                parent.onSelectionChange()
                parent.onTextEdited?(updates.text, false)
                isApplyingProgrammaticChange = false
            }
        }

        func isLiveEditing(in textView: UITextView) -> Bool {
            textView.isFirstResponder
        }

        func syncIfNeeded(text: String, selectedRange: NSRange, in textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }

            let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )

            if usesWysiwygEditing {
                if isLiveEditing(in: textView) { return }
                applyContent(text, selectedRange: selectedRange, to: textView)
                return
            }

            if isLiveEditing(in: textView), textView.text != text {
                return
            }

            if usesAttachments {
                if NoteImageEmbedAttributedSupport.shouldRebuildAttributedText(
                    bindingMarkdown: text,
                    currentAttributed: textView.attributedText,
                    vaultURL: parent.vaultURL
                ) {
                    applyContent(text, selectedRange: selectedRange, to: textView)
                } else if !isLiveEditing(in: textView) {
                    let expected = NoteImageEmbedAttributedSupport.attributedRange(
                        fromMarkdownRange: selectedRange,
                        in: text,
                        vaultURL: parent.vaultURL
                    )
                    if textView.selectedRange != expected {
                        textView.selectedRange = expected
                    }
                }
                return
            }

            if textView.text != text {
                applyContent(text, selectedRange: selectedRange, to: textView)
            } else if !isLiveEditing(in: textView) {
                if textView.selectedRange != selectedRange {
                    textView.selectedRange = selectedRange
                }
                restyle(textView)
            }
        }

        func applyContent(_ content: String, selectedRange: NSRange, to textView: UITextView) {
            isApplyingProgrammaticChange = true
            defer { isApplyingProgrammaticChange = false }

            let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )
            let styleSelection = styleSelection(for: textView, selectedRange: selectedRange)

            NoteUndoRegistration.perform(on: textView.undoManager) {
                textView.attributedText = NoteTextEditingCoordinatorSupport.styledContent(
                    content,
                    selectedRange: styleSelection,
                    fontSize: parent.fontSize,
                    editorBackground: parent.editorBackground,
                    vaultURL: parent.vaultURL,
                    hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                    hideTaskListMarkers: parent.hideTaskListMarkers,
                    embeddedInCanvas: parent.embeddedInCanvas
                )
                if usesAttachments {
                    textView.selectedRange = NoteImageEmbedAttributedSupport.attributedRange(
                        fromMarkdownRange: selectedRange,
                        in: content,
                        vaultURL: parent.vaultURL
                    )
                } else if usesWysiwygEditing {
                    textView.selectedRange = MarkdownWysiwygEditingSupport.displayRange(
                        fromMarkdown: selectedRange,
                        in: content,
                        fontSize: parent.fontSize,
                        editorBackground: parent.editorBackground,
                        hideTaskListMarkers: parent.hideTaskListMarkers
                    )
                } else {
                    textView.selectedRange = clampedRange(selectedRange, in: content)
                }
            }
            updateCaretRect(for: textView)
            (textView as? NoteEditingUITextView)?.refreshFormattingToolbar()
            if parent.embeddedInCanvas {
                relayoutEmbeddedCanvas(in: textView)
                if let scrollView = containerView?.scrollView {
                    emitContentScroll(from: scrollView, deferUpdate: true)
                }
            }
        }

        private func relayoutEmbeddedCanvas(in textView: UITextView) {
            containerView?.relayoutDocumentTextView()
        }

        private func scrollEmbeddedCaretIntoViewIfNeeded(for textView: UITextView) {
            if parent.embeddedInCanvas {
                if let scrollView = containerView?.scrollView {
                    CanvasNoteEditorScrollSupport.scrollCaretIntoViewIfNeeded(
                        scrollView,
                        textView: textView,
                        fontSize: parent.fontSize
                    )
                } else {
                    CanvasNoteEditorScrollSupport.scrollCaretIntoViewIfNeeded(
                        textView,
                        fontSize: parent.fontSize
                    )
                }
                return
            }

            guard parent.fillsAvailableHeight else { return }
            NoteStandaloneEditorKeyboardSupport.scrollSelectionIntoView(textView, fontSize: parent.fontSize)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = true
            guard let noteTextView = textView as? NoteEditingUITextView else { return }
            noteTextView.configureToolbarBridge(parent.toolbarBridge)
            noteTextView.refreshFormattingToolbar()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = false
            if !usesWysiwygEditing {
                restyle(textView)
            }
            (textView as? NoteEditingUITextView)?.refreshFormattingToolbar()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }

            let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )

            var newText: String
            var newRange: NSRange

            if usesAttachments {
                newText = NoteImageEmbedAttributedSupport.markdownPreservingEmbeds(
                    from: textView.attributedText,
                    previousMarkdown: parent.text,
                    vaultURL: parent.vaultURL
                )
                newRange = NoteImageEmbedAttributedSupport.markdownRange(
                    fromAttributedRange: textView.selectedRange,
                    in: newText,
                    vaultURL: parent.vaultURL
                )
                restyle(textView)
            } else if usesWysiwygEditing {
                return
            } else {
                restyle(textView)
                newText = textView.text ?? ""
                newRange = textView.selectedRange
                if parent.embeddedInCanvas, parent.hideResolvedImageEmbeds {
                    let sanitized = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(
                        in: newText,
                        vaultURL: parent.vaultURL,
                        selectedRange: newRange
                    )
                    if sanitized.text != newText {
                        isApplyingProgrammaticChange = true
                        NoteUndoRegistration.perform(on: textView.undoManager) {
                            textView.attributedText = NoteTextEditingCoordinatorSupport.styledContent(
                                sanitized.text,
                                selectedRange: sanitized.selectedRange ?? newRange,
                                fontSize: parent.fontSize,
                                editorBackground: parent.editorBackground,
                                vaultURL: parent.vaultURL,
                                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                                hideTaskListMarkers: parent.hideTaskListMarkers,
                                embeddedInCanvas: parent.embeddedInCanvas
                            )
                            textView.selectedRange = sanitized.selectedRange ?? newRange
                        }
                        isApplyingProgrammaticChange = false
                        newText = sanitized.text
                        newRange = sanitized.selectedRange ?? newRange
                    }
                }
            }

            let fromTextUndo = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
            (textView as? NoteEditingUITextView)?.refreshFormattingToolbar()
            parent.text = newText
            parent.selectedRange = newRange
            Task { @MainActor in
                updateCaretRect(for: textView)
                if parent.embeddedInCanvas {
                    relayoutEmbeddedCanvas(in: textView)
                    scrollEmbeddedCaretIntoViewIfNeeded(for: textView)
                    updateCaretRect(for: textView)
                } else if parent.fillsAvailableHeight {
                    scrollEmbeddedCaretIntoViewIfNeeded(for: textView)
                }
                if let scrollView = containerView?.scrollView {
                    emitContentScroll(from: scrollView, deferUpdate: true)
                } else {
                    emitContentScroll(from: textView, deferUpdate: true)
                }
                parent.onSelectionChange()
                parent.onTextEdited?(newText, fromTextUndo)
            }
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            parent.onImageAttachmentDrop != nil && session.hasItemsConforming(toTypeIdentifiers: [
                UTType.image.identifier,
                UTType.fileURL.identifier,
            ])
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: canHandleImageDrop(session) ? .copy : .cancel)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            guard let handler = parent.onImageAttachmentDrop else { return }
            for item in session.items {
                NoteImageDropSupport.loadData(from: item.itemProvider) { data, name in
                    _ = handler(data, name)
                }
                return
            }
        }

        private func canHandleImageDrop(_ session: UIDropSession) -> Bool {
            session.hasItemsConforming(toTypeIdentifiers: [
                UTType.image.identifier,
                UTType.fileURL.identifier,
            ])
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            let newRange = NoteTextEditingCoordinatorSupport.markdownBindingRange(
                fromAttributedRange: textView.selectedRange,
                markdown: parent.text,
                embeddedInCanvas: parent.embeddedInCanvas,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers
            )
            if !NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            ), !usesWysiwygEditing {
                restyle(textView)
            }
            updateEditingChrome(for: textView)
            (textView as? NoteEditingUITextView)?.refreshFormattingToolbar()
            Task { @MainActor in
                parent.selectedRange = newRange
                if parent.embeddedInCanvas {
                    scrollEmbeddedCaretIntoViewIfNeeded(for: textView)
                } else if parent.fillsAvailableHeight {
                    scrollEmbeddedCaretIntoViewIfNeeded(for: textView)
                }
                updateCaretRect(for: textView)
                parent.onSelectionChange()
            }
        }

        private func restyle(_ textView: UITextView, hideAllDelimiters explicit: Bool? = nil) {
            guard !usesWysiwygEditing else { return }
            // Canvas cards may reveal delimiters near the caret while actively editing inline markdown.
            let hide = explicit ?? !parent.embeddedInCanvas
            let selectedOverride = hide
                ? NSRange(location: NSNotFound, length: 0)
                : nil
            NoteTextEditingCoordinatorSupport.restyleInPlace(
                textView: textView,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth,
                hideTaskListMarkers: parent.hideTaskListMarkers,
                selectedRangeOverride: selectedOverride
            )
        }

        private func styleSelection(for textView: UITextView, selectedRange: NSRange) -> NSRange {
            if parent.embeddedInCanvas, isLiveEditing(in: textView) {
                return selectedRange
            }
            return NSRange(location: NSNotFound, length: 0)
        }

        func restyleForLayoutRefresh(in textView: UITextView, container: CanvasNoteUITextContainerView?) {
            restyle(textView)
            if parent.embeddedInCanvas {
                container?.relayoutDocumentTextView()
            }
        }

        func refreshLayoutIfNeeded(token: Int, in textView: UITextView, container: CanvasNoteUITextContainerView?) {
            guard token != lastLayoutRefreshToken else { return }
            lastLayoutRefreshToken = token
            if NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            ) {
                applyContent(parent.text, selectedRange: parent.selectedRange, to: textView)
            } else {
                restyleForLayoutRefresh(in: textView, container: container)
                if let scrollView = container?.scrollView {
                    emitContentScroll(from: scrollView, deferUpdate: true)
                } else if parent.embeddedInCanvas {
                    emitContentScroll(from: textView, deferUpdate: true)
                }
                return
            }
            if parent.embeddedInCanvas {
                container?.relayoutDocumentTextView()
            }
            if let scrollView = container?.scrollView {
                emitContentScroll(from: scrollView, deferUpdate: true)
            } else if parent.embeddedInCanvas {
                emitContentScroll(from: textView, deferUpdate: true)
            }
        }

        func revealSelectionIfNeeded(token: Int, in textView: UITextView) {
            guard token != lastSelectionRevealToken else { return }
            lastSelectionRevealToken = token
            applyContent(parent.text, selectedRange: parent.selectedRange, to: textView)
            scrollEmbeddedCaretIntoViewIfNeeded(for: textView)
            if parent.fillsAvailableHeight {
                NoteStandaloneEditorKeyboardSupport.scrollSelectionIntoView(textView, fontSize: parent.fontSize)
            }
        }

        private func updateEditingChrome(for textView: UITextView) {
            let scrollOffset = contentScrollOffset(for: textView)
            let rect = NoteEditingChromeSupport.caretRect(
                in: textView,
                fontSize: parent.fontSize,
                contentScrollOffset: scrollOffset
            )
            let selection = parent.showsCustomEditingChrome
                ? NoteEditingChromeSupport.selectionRects(in: textView, contentScrollOffset: scrollOffset)
                : nil
            let suggestAnchorRect = computedSuggestAnchor(for: textView, scrollOffset: scrollOffset)
            Task { @MainActor in
                parent.caretRect = rect
                if let selection {
                    parent.selectionRects = selection
                } else if !parent.showsCustomEditingChrome {
                    parent.selectionRects = []
                }
                parent.suggestAnchorRect = suggestAnchorRect
            }
        }

        private func computedSuggestAnchor(for textView: UITextView, scrollOffset: CGPoint) -> CGRect {
            let cursor = parent.selectedRange.location + parent.selectedRange.length
            guard let query = WikilinkEditorSupport.activeQuery(in: parent.text, cursor: cursor) else {
                return .zero
            }
            let usesAttachments = NoteImageEmbedAttributedSupport.usesInlineAttachments(
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                vaultURL: parent.vaultURL,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )
            let anchorIndex = usesAttachments
                ? NoteImageEmbedAttributedSupport.attributedRange(
                    fromMarkdownRange: NSRange(location: query.replaceRange.location, length: 0),
                    in: parent.text,
                    vaultURL: parent.vaultURL
                ).location
                : query.replaceRange.location
            return NoteEditingChromeSupport.wikilinkSuggestAnchor(
                in: textView,
                characterIndex: anchorIndex,
                fontSize: parent.fontSize,
                contentScrollOffset: scrollOffset
            )
        }

        private func updateSuggestAnchor(in textView: UITextView, scrollOffset: CGPoint) {
            let anchor = computedSuggestAnchor(for: textView, scrollOffset: scrollOffset)
            Task { @MainActor in
                parent.suggestAnchorRect = anchor
            }
        }

        private func updateCaretRect(for textView: UITextView) {
            updateEditingChrome(for: textView)
        }

        func syncEditingChrome(in textView: UITextView) {
            updateEditingChrome(for: textView)
        }

        private func scrollCaretIntoView(_ textView: UITextView) {
            scrollEmbeddedCaretIntoViewIfNeeded(for: textView)
            updateCaretRect(for: textView)
        }

        private func clampedRange(_ range: NSRange, in content: String) -> NSRange {
            let length = (content as NSString).length
            let location = min(max(range.location, 0), length)
            let upper = min(range.location + range.length, length)
            return NSRange(location: location, length: max(0, upper - location))
        }
    }
}

#endif
