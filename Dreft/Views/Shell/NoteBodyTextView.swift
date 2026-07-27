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
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return .zero }

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
        return convert(rect, in: textView)
    }

    private static func convert(_ rect: CGRect, in textView: NSTextView) -> CGRect {
        var converted = rect
        converted.origin.x += textView.textContainerInset.width
        converted.origin.y += textView.textContainerInset.height
        if let scrollView = textView.enclosingScrollView {
            let scrollOrigin = scrollView.contentView.bounds.origin
            converted.origin.x -= scrollOrigin.x
            converted.origin.y -= scrollOrigin.y
        }
        return converted
    }
    #elseif os(iOS)
    static func selectionRects(in textView: UITextView) -> [CGRect] {
        guard let range = textView.selectedTextRange, !range.isEmpty else { return [] }
        return textView.selectionRects(for: range).map { item in
            var rect = item.rect
            rect.origin.x -= textView.contentOffset.x
            rect.origin.y -= textView.contentOffset.y
            rect.origin.x += textView.textContainerInset.left
            rect.origin.y += textView.textContainerInset.top
            return rect
        }
    }

    static func caretRect(in textView: UITextView, fontSize: CGFloat) -> CGRect {
        guard let range = textView.selectedTextRange else { return .zero }
        var rect = textView.caretRect(for: range.end)
        rect.origin.x -= textView.contentOffset.x
        rect.origin.y -= textView.contentOffset.y
        rect.origin.x += textView.textContainerInset.left
        rect.origin.y += textView.textContainerInset.top
        if rect.height < 1 {
            rect.size.height = fontSize * 1.2
        }
        return rect
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
    /// Plain-text edits; `fromTextUndo` is true for NSTextView/UITextView ⌘Z steps.
    var onTextEdited: ((String, Bool) -> Void)?
    var toolbarBridge: NoteFormattingToolbarBridge? = nil
    var onImageAttachmentDrop: ((Data, String?) -> Bool)? = nil
    var layoutRefreshToken: Int = 0
    var onContentScroll: ((CanvasNoteScrollMetrics) -> Void)? = nil

    @State private var activeQuery: WikilinkActiveQuery?

    private var suggestions: [WorkspaceFileEntry] {
        guard let activeQuery else { return [] }
        return WikilinkSuggestSearch.results(matching: activeQuery.query, in: files)
    }

    var body: some View {
        Group {
            if embeddedInCanvas {
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
            NoteBodyTextViewRepresentable(
                text: $text,
                selectedRange: $selectedRange,
                caretRect: $caretRect,
                selectionRects: $selectionRects,
                isFocused: isFocused,
                fontSize: fontSize,
                embeddedInCanvas: embeddedInCanvas,
                containerSize: containerSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                onSelectionChange: refreshActiveQuery,
                onSuggestKey: handleSuggestKey,
                onTextEdited: onTextEdited,
                toolbarBridge: toolbarBridge,
                onImageAttachmentDrop: onImageAttachmentDrop,
                layoutRefreshToken: layoutRefreshToken,
                onContentScroll: onContentScroll
            )
            .frame(maxWidth: embeddedInCanvas ? .infinity : nil, maxHeight: embeddedInCanvas ? .infinity : nil)
            .frame(minHeight: embeddedInCanvas ? 0 : minBodyHeight)
            .clipShape(RoundedRectangle(cornerRadius: embeddedInCanvas ? 4 : 0))

            if activeQuery != nil, !suggestions.isEmpty {
                WikilinkSuggestPopover(
                    results: suggestions,
                    selectedIndex: suggestSelectedIndex
                )
                .offset(x: caretRect.minX, y: caretRect.maxY + 6)
                .zIndex(20)
            }
        }
    }

    private func refreshActiveQuery() {
        let cursor = selectedRange.location + selectedRange.length
        let query = WikilinkEditorSupport.activeQuery(in: text, cursor: cursor)
        Task { @MainActor in
            if query != activeQuery {
                activeQuery = query
                if query != nil {
                    suggestSelectedIndex = 0
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
    private static func styledContent(
        _ content: String,
        selectedRange: NSRange,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL?,
        hideResolvedImageEmbeds: Bool,
        imageEmbedMaxWidth: CGFloat? = nil
    ) -> NSAttributedString {
        WikilinkEditorSupport.attributedString(
            for: content,
            selectedRange: selectedRange,
            fontSize: fontSize,
            hiddenDelimiterOn: editorBackground,
            vaultURL: vaultURL,
            hideResolvedImageEmbeds: hideResolvedImageEmbeds,
            imageEmbedMaxWidth: imageEmbedMaxWidth
        )
    }

    static func applyMarkdownEdit(
        _ action: MarkdownEditAction,
        textView: AnyObject,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil
    ) -> (text: String, selectedRange: NSRange) {
        #if os(macOS)
        guard let textView = textView as? NSTextView else { return ("", NSRange(location: 0, length: 0)) }
        let range = textView.selectedRange()
        let source = textView.string
        #else
        guard let textView = textView as? UITextView else { return ("", NSRange(location: 0, length: 0)) }
        let range = textView.selectedRange
        let source = textView.text ?? ""
        #endif

        let result = MarkdownEditingSupport.apply(action, text: source, selectedRange: range)

        #if os(macOS)
        NoteUndoRegistration.perform(on: textView.undoManager) {
            if source != result.text {
                let styled = styledContent(
                    result.text,
                    selectedRange: result.selectedRange,
                    fontSize: fontSize,
                    editorBackground: editorBackground,
                    vaultURL: vaultURL,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: imageEmbedMaxWidth
                )
                textView.textStorage?.setAttributedString(styled)
            } else {
                restyleInPlace(
                    textView: textView,
                    fontSize: fontSize,
                    editorBackground: editorBackground,
                    vaultURL: vaultURL,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: imageEmbedMaxWidth
                )
            }
            textView.setSelectedRange(result.selectedRange)
        }
        #else
        NoteUndoRegistration.perform(on: textView.undoManager) {
            if source != result.text {
                textView.attributedText = styledContent(
                    result.text,
                    selectedRange: result.selectedRange,
                    fontSize: fontSize,
                    editorBackground: editorBackground,
                    vaultURL: vaultURL,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: imageEmbedMaxWidth
                )
            } else {
                restyleInPlace(
                    textView: textView,
                    fontSize: fontSize,
                    editorBackground: editorBackground,
                    vaultURL: vaultURL,
                    hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: imageEmbedMaxWidth
                )
            }
            textView.selectedRange = result.selectedRange
        }
        #endif

        return (result.text, result.selectedRange)
    }

    static func insertSnippet(
        _ snippet: String,
        textView: AnyObject,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil
    ) -> (text: String, selectedRange: NSRange) {
        #if os(macOS)
        guard let textView = textView as? NSTextView else { return ("", NSRange(location: 0, length: 0)) }
        let range = textView.selectedRange()
        let source = textView.string
        #else
        guard let textView = textView as? UITextView else { return ("", NSRange(location: 0, length: 0)) }
        let range = textView.selectedRange
        let source = textView.text ?? ""
        #endif

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
        NoteUndoRegistration.perform(on: textView.undoManager) {
            let styled = styledContent(
                finalResult.text,
                selectedRange: finalResult.selectedRange,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth
            )
            textView.textStorage?.setAttributedString(styled)
            textView.setSelectedRange(finalResult.selectedRange)
        }
        #else
        NoteUndoRegistration.perform(on: textView.undoManager) {
            textView.attributedText = styledContent(
                finalResult.text,
                selectedRange: finalResult.selectedRange,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth
            )
            textView.selectedRange = finalResult.selectedRange
        }
        #endif

        return (finalResult.text, finalResult.selectedRange)
    }

    static func applyEditedText(
        _ result: (text: String, selectedRange: NSRange),
        textView: AnyObject,
        fontSize: CGFloat,
        editorBackground: Color,
        vaultURL: URL? = nil,
        hideResolvedImageEmbeds: Bool = false,
        imageEmbedMaxWidth: CGFloat? = nil
    ) -> (text: String, selectedRange: NSRange) {
        #if os(macOS)
        guard let textView = textView as? NSTextView else { return ("", NSRange(location: 0, length: 0)) }
        NoteUndoRegistration.perform(on: textView.undoManager) {
            let styled = styledContent(
                result.text,
                selectedRange: result.selectedRange,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth
            )
            textView.textStorage?.setAttributedString(styled)
            textView.setSelectedRange(result.selectedRange)
        }
        #else
        guard let textView = textView as? UITextView else { return ("", NSRange(location: 0, length: 0)) }
        NoteUndoRegistration.perform(on: textView.undoManager) {
            textView.attributedText = styledContent(
                result.text,
                selectedRange: result.selectedRange,
                fontSize: fontSize,
                editorBackground: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth
            )
            textView.selectedRange = result.selectedRange
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
        imageEmbedMaxWidth: CGFloat? = nil
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
                imageEmbedMaxWidth: imageEmbedMaxWidth
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
        imageEmbedMaxWidth: CGFloat? = nil
    ) {
        let storage = textView.textStorage
        let selected = textView.selectedRange
        NoteUndoRegistration.perform(on: textView.undoManager) {
            storage.beginEditing()
            WikilinkEditorSupport.restyleInPlace(
                storage,
                selectedRange: selected,
                fontSize: fontSize,
                hiddenDelimiterOn: editorBackground,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: hideResolvedImageEmbeds,
                imageEmbedMaxWidth: imageEmbedMaxWidth
            )
            storage.endEditing()
            if textView.selectedRange != selected {
                textView.selectedRange = selected
            }
        }
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
}

final class NoteEditingNSTextView: NSTextView {
    weak var editingDelegate: NoteEditingTextViewDelegate?
    var imageDropHandler: ((Data, String?) -> Bool)?

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForImageDragTypes()
    }

    func registerForImageDragTypes() {
        registerForDraggedTypes([
            .fileURL,
            .png,
            .tiff,
            NSPasteboard.PasteboardType(UTType.image.identifier),
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ])
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
    var isFocused: FocusState<Bool>.Binding
    var fontSize: CGFloat
    var embeddedInCanvas: Bool
    var containerSize: CGSize?
    var editorBackground: Color
    var vaultURL: URL?
    var hideResolvedImageEmbeds: Bool
    var onSelectionChange: () -> Void
    var onSuggestKey: (WikilinkSuggestKey) -> Bool
    var onTextEdited: ((String, Bool) -> Void)?
    var toolbarBridge: NoteFormattingToolbarBridge? = nil
    var onImageAttachmentDrop: ((Data, String?) -> Bool)? = nil
    var layoutRefreshToken: Int = 0
    var onContentScroll: ((CanvasNoteScrollMetrics) -> Void)? = nil

    var imageEmbedLayoutWidth: CGFloat? {
        guard embeddedInCanvas, hideResolvedImageEmbeds,
              let width = containerSize?.width, width > 1 else { return nil }
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
        context.coordinator.syncIfNeeded(text: text, selectedRange: selectedRange, in: textView)
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
                context.coordinator.emitContentScroll(from: scrollView, textView: textView)
            }
            if isFocused.wrappedValue {
                DispatchQueue.main.async {
                    container.relayoutDocumentTextView()
                }
            }
        }

        if isFocused.wrappedValue, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    private func configure(textView: NoteEditingNSTextView, coordinator: Coordinator) {
        textView.delegate = coordinator
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
                .backgroundColor: NSColor(AppColors.selectionStroke).withAlphaComponent(0.22),
            ]
        } else if embeddedInCanvas {
            textView.insertionPointColor = NSColor(AppColors.textPrimary)
        }
        textView.registerForImageDragTypes()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NoteEditingNSTextViewDelegate {
        var parent: NoteBodyTextViewRepresentable
        weak var textView: NoteEditingNSTextView?
        weak var containerView: CanvasNoteTextContainerView?
        private var isApplyingProgrammaticChange = false
        private var lastLayoutRefreshToken = -1

        init(parent: NoteBodyTextViewRepresentable) {
            self.parent = parent
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
            let selected = textView.selectedRange()
            let source = textView.string

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
                guard let target = NoteCardEmbedEditingSupport.moveDownPastImageEmbed(
                    in: source,
                    selectedRange: selected,
                    vaultURL: parent.vaultURL
                ) else { return false }
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
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
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
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
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
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
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

        func syncIfNeeded(text: String, selectedRange: NSRange, in textView: NSTextView) {
            guard !isApplyingProgrammaticChange else { return }
            if textView.string != text {
                applyContent(text, selectedRange: selectedRange, to: textView)
            } else if textView.selectedRange() != selectedRange {
                textView.setSelectedRange(selectedRange)
                restyle(textView)
            }
        }

        func applyContent(_ content: String, selectedRange: NSRange, to textView: NSTextView) {
            isApplyingProgrammaticChange = true
            defer { isApplyingProgrammaticChange = false }

            NoteUndoRegistration.perform(on: textView.undoManager) {
                let styled = WikilinkEditorSupport.attributedString(
                    for: content,
                    selectedRange: selectedRange,
                    fontSize: parent.fontSize,
                    hiddenDelimiterOn: parent.editorBackground,
                    vaultURL: parent.vaultURL,
                    hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
                )
                textView.textStorage?.setAttributedString(styled)
                textView.setSelectedRange(clampedRange(selectedRange, in: content))
            }
            updateCaretRect(for: textView)
            containerView?.relayoutDocumentTextView()
            if let scrollView = containerView?.scrollView {
                emitContentScroll(from: scrollView, textView: textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingProgrammaticChange else { return }
            restyle(textView)
            var newText = textView.string
            var newRange = textView.selectedRange()
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
            let fromTextUndo = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
            Task { @MainActor in
                parent.text = newText
                parent.selectedRange = newRange
                updateCaretRect(for: textView)
                scrollCaretIntoView(textView)
                containerView?.relayoutDocumentTextView()
                if let scrollView = containerView?.scrollView {
                    emitContentScroll(from: scrollView, textView: textView)
                }
                parent.onSelectionChange()
                parent.onTextEdited?(newText, fromTextUndo)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingProgrammaticChange else { return }
            let newRange = textView.selectedRange()
            restyle(textView)
            Task { @MainActor in
                parent.selectedRange = newRange
                updateCaretRect(for: textView)
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
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
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
            restyle(textView)
            container?.relayoutDocumentTextView()
            if let scrollView = containerView?.scrollView {
                emitContentScroll(from: scrollView, textView: textView)
            }
        }

        func emitContentScroll(from scrollView: NSScrollView, textView: NSTextView) {
            guard let handler = parent.onContentScroll else { return }
            let metrics = CanvasNoteScrollMetrics(
                offset: scrollView.contentView.bounds.origin,
                contentHeight: textView.frame.height,
                viewportHeight: scrollView.contentView.bounds.height
            )
            handler(metrics)
        }

        private func updateEditingChrome(for textView: NSTextView) {
            guard parent.embeddedInCanvas else { return }
            let rect = NoteEditingChromeSupport.caretRect(in: textView, fontSize: parent.fontSize)
            let rects = NoteEditingChromeSupport.selectionRects(in: textView)
            Task { @MainActor in
                parent.caretRect = rect
                parent.selectionRects = rects
            }
        }

        private func updateCaretRect(for textView: NSTextView) {
            updateEditingChrome(for: textView)
        }

        func scrollCaretIntoView(_ textView: NSTextView) {
            guard parent.embeddedInCanvas else { return }
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

final class NoteEditingUITextView: UITextView {
    weak var editingDelegate: NoteEditingTextViewDelegate?
    var toolbarBridge: NoteFormattingToolbarBridge?
    weak var dropDelegate: UIDropInteractionDelegate?
    var imageDropHandler: ((Data, String?) -> Bool)?
    var onScroll: (() -> Void)?

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
        } else {
            inputAccessoryView = UIView(frame: .zero)
            if isFirstResponder {
                reloadInputViews()
            }
        }
        bridge?.scheduleRefresh()
    }

    func refreshFormattingToolbar() {
        toolbarBridge?.scheduleRefresh()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            toolbarBridge?.textView = self
            toolbarBridge?.attachInputAccessory(to: self)
            refreshFormattingToolbar()
            reloadInputViews()
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
    var isFocused: FocusState<Bool>.Binding
    var fontSize: CGFloat
    var embeddedInCanvas: Bool
    var containerSize: CGSize?
    var editorBackground: Color
    var vaultURL: URL?
    var hideResolvedImageEmbeds: Bool
    var onSelectionChange: () -> Void
    var onSuggestKey: (WikilinkSuggestKey) -> Bool
    var onTextEdited: ((String, Bool) -> Void)?
    var toolbarBridge: NoteFormattingToolbarBridge? = nil
    var onImageAttachmentDrop: ((Data, String?) -> Bool)? = nil
    var layoutRefreshToken: Int = 0
    var onContentScroll: ((CanvasNoteScrollMetrics) -> Void)? = nil

    var imageEmbedLayoutWidth: CGFloat? {
        guard embeddedInCanvas, hideResolvedImageEmbeds,
              let width = containerSize?.width, width > 1 else { return nil }
        return max(1, width)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> NoteEditingUITextView {
        let textView = NoteEditingUITextView()
        textView.editingDelegate = context.coordinator
        textView.delegate = context.coordinator
        textView.dropDelegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = UIColor(AppColors.textPrimary)
        textView.isScrollEnabled = embeddedInCanvas
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        if embeddedInCanvas && hideResolvedImageEmbeds {
            textView.tintColor = .clear
        } else if embeddedInCanvas {
            textView.tintColor = UIColor(AppColors.textPrimary)
        }
        textView.imageDropHandler = onImageAttachmentDrop
        textView.refreshDropInteraction()
        context.coordinator.attach(textView: textView)
        textView.configureToolbarBridge(toolbarBridge)
        context.coordinator.applyContent(text, selectedRange: selectedRange, to: textView)
        return textView
    }

    func updateUIView(_ textView: NoteEditingUITextView, context: Context) {
        context.coordinator.parent = self
        textView.configureToolbarBridge(toolbarBridge)
        textView.imageDropHandler = onImageAttachmentDrop
        textView.refreshDropInteraction()
        context.coordinator.syncIfNeeded(text: text, selectedRange: selectedRange, in: textView)
        if let containerSize, embeddedInCanvas, containerSize.width > 1, containerSize.height > 1 {
            textView.bounds.size = containerSize
        }
        context.coordinator.refreshLayoutIfNeeded(
            token: layoutRefreshToken,
            in: textView
        )
        if isFocused.wrappedValue, !textView.isFirstResponder {
            _ = textView.becomeFirstResponder()
        }
        if embeddedInCanvas {
            context.coordinator.emitContentScroll(from: textView)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, NoteEditingUITextViewDelegate, UIDropInteractionDelegate {
        var parent: NoteBodyTextViewRepresentable
        weak var textView: NoteEditingUITextView?
        private var isApplyingProgrammaticChange = false
        private var lastLayoutRefreshToken = -1

        init(parent: NoteBodyTextViewRepresentable) {
            self.parent = parent
        }

        func attach(textView: NoteEditingUITextView) {
            self.textView = textView
            textView.onScroll = { [weak self] in
                guard let self, let textView = self.textView else { return }
                self.emitContentScroll(from: textView)
                self.updateCaretRect(for: textView)
            }
            if parent.embeddedInCanvas {
                CanvasNoteCardScrollBridge.register(owner: "edit") { [weak self] delta in
                    guard let self, let textView = self.textView else { return .none }
                    let result = CanvasNoteCardScrollBridge.scroll(textView, by: delta)
                    self.emitContentScroll(from: textView)
                    self.updateCaretRect(for: textView)
                    return result
                }
            }
        }

        func emitContentScroll(from textView: UITextView) {
            guard let handler = parent.onContentScroll else { return }
            let metrics = CanvasNoteScrollMetrics(
                offset: textView.contentOffset,
                contentHeight: textView.contentSize.height,
                viewportHeight: textView.bounds.height
            )
            handler(metrics)
        }

        func noteEditingTextView(_ textView: NoteEditingUITextView, apply action: MarkdownEditAction) {
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.applyMarkdownEdit(
                action,
                textView: textView,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )
            textView.refreshFormattingToolbar()
            Task { @MainActor in
                parent.text = updates.text
                parent.selectedRange = updates.selectedRange
                updateCaretRect(for: textView)
                parent.onSelectionChange()
                parent.onTextEdited?(updates.text, false)
                isApplyingProgrammaticChange = false
            }
        }

        func noteEditingTextView(_ textView: NoteEditingUITextView, insertSnippet snippet: String) {
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.insertSnippet(
                snippet,
                textView: textView,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )
            textView.refreshFormattingToolbar()
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

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n",
                  parent.embeddedInCanvas,
                  parent.hideResolvedImageEmbeds,
                  !isApplyingProgrammaticChange else { return true }
            let source = textView.text ?? ""
            guard let result = NoteCardEmbedEditingSupport.newlineBelowImageEmbed(
                in: source,
                selectedRange: range,
                vaultURL: parent.vaultURL
            ) else { return true }

            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.applyEditedText(
                result,
                textView: textView,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )
            (textView as? NoteEditingUITextView)?.refreshFormattingToolbar()
            Task { @MainActor in
                parent.text = updates.text
                parent.selectedRange = updates.selectedRange
                updateCaretRect(for: textView)
                parent.onSelectionChange()
                parent.onTextEdited?(updates.text, false)
                isApplyingProgrammaticChange = false
            }
            return false
        }

        func syncIfNeeded(text: String, selectedRange: NSRange, in textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            if textView.text != text {
                applyContent(text, selectedRange: selectedRange, to: textView)
            } else if textView.selectedRange != selectedRange {
                textView.selectedRange = selectedRange
                restyle(textView)
            }
        }

        func applyContent(_ content: String, selectedRange: NSRange, to textView: UITextView) {
            isApplyingProgrammaticChange = true
            defer { isApplyingProgrammaticChange = false }

            NoteUndoRegistration.perform(on: textView.undoManager) {
                textView.attributedText = WikilinkEditorSupport.attributedString(
                    for: content,
                    selectedRange: selectedRange,
                    fontSize: parent.fontSize,
                    hiddenDelimiterOn: parent.editorBackground,
                    vaultURL: parent.vaultURL,
                    hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                    imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
                )
                textView.selectedRange = clampedRange(selectedRange, in: content)
            }
            updateCaretRect(for: textView)
            (textView as? NoteEditingUITextView)?.refreshFormattingToolbar()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            restyle(textView)
            var newText = textView.text ?? ""
            var newRange = textView.selectedRange
            if parent.embeddedInCanvas, parent.hideResolvedImageEmbeds {
                let sanitized = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(
                    in: newText,
                    vaultURL: parent.vaultURL,
                    selectedRange: newRange
                )
                if sanitized.text != newText {
                    isApplyingProgrammaticChange = true
                    NoteUndoRegistration.perform(on: textView.undoManager) {
                        textView.attributedText = WikilinkEditorSupport.attributedString(
                            for: sanitized.text,
                            selectedRange: sanitized.selectedRange ?? newRange,
                            fontSize: parent.fontSize,
                            hiddenDelimiterOn: parent.editorBackground,
                            vaultURL: parent.vaultURL,
                            hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                            imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
                        )
                        textView.selectedRange = sanitized.selectedRange ?? newRange
                    }
                    isApplyingProgrammaticChange = false
                    newText = sanitized.text
                    newRange = sanitized.selectedRange ?? newRange
                }
            }
            let fromTextUndo = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
            (textView as? NoteEditingUITextView)?.refreshFormattingToolbar()
            Task { @MainActor in
                parent.text = newText
                parent.selectedRange = newRange
                updateCaretRect(for: textView)
                scrollCaretIntoView(textView)
                emitContentScroll(from: textView)
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
            let newRange = textView.selectedRange
            restyle(textView)
            (textView as? NoteEditingUITextView)?.refreshFormattingToolbar()
            Task { @MainActor in
                parent.selectedRange = newRange
                updateCaretRect(for: textView)
                parent.onSelectionChange()
            }
        }

        private func restyle(_ textView: UITextView) {
            NoteTextEditingCoordinatorSupport.restyleInPlace(
                textView: textView,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground,
                vaultURL: parent.vaultURL,
                hideResolvedImageEmbeds: parent.hideResolvedImageEmbeds,
                imageEmbedMaxWidth: parent.imageEmbedLayoutWidth
            )
        }

        func restyleForLayoutRefresh(in textView: UITextView) {
            restyle(textView)
        }

        func refreshLayoutIfNeeded(token: Int, in textView: UITextView) {
            guard token != lastLayoutRefreshToken else { return }
            lastLayoutRefreshToken = token
            restyle(textView)
            emitContentScroll(from: textView)
        }

        private func updateEditingChrome(for textView: UITextView) {
            guard parent.embeddedInCanvas else { return }
            let rect = NoteEditingChromeSupport.caretRect(in: textView, fontSize: parent.fontSize)
            let rects = NoteEditingChromeSupport.selectionRects(in: textView)
            Task { @MainActor in
                parent.caretRect = rect
                parent.selectionRects = rects
            }
        }

        private func updateCaretRect(for textView: UITextView) {
            updateEditingChrome(for: textView)
        }

        private func scrollCaretIntoView(_ textView: UITextView) {
            guard parent.embeddedInCanvas else { return }
            textView.scrollRangeToVisible(textView.selectedRange)
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
