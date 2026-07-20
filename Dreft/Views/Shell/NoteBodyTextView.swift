import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
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

struct NoteBodyTextView: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var caretRect: CGRect
    var isFocused: FocusState<Bool>.Binding
    let files: [WorkspaceFileEntry]
    @Binding var suggestSelectedIndex: Int
    var fontSize: CGFloat = WikilinkEditorSupport.bodyFontSize
    var minBodyHeight: CGFloat = 520
    var embeddedInCanvas: Bool = false
    var editorBackground: Color = AppColors.canvasBackground
    /// Plain-text edits; `fromTextUndo` is true for NSTextView/UITextView ⌘Z steps.
    var onTextEdited: ((String, Bool) -> Void)?

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
                isFocused: isFocused,
                fontSize: fontSize,
                embeddedInCanvas: embeddedInCanvas,
                containerSize: containerSize,
                editorBackground: editorBackground,
                onSelectionChange: refreshActiveQuery,
                onSuggestKey: handleSuggestKey,
                onTextEdited: onTextEdited
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
    static func applyMarkdownEdit(
        _ action: MarkdownEditAction,
        textView: AnyObject,
        fontSize: CGFloat,
        editorBackground: Color
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
                textView.textStorage?.replaceCharacters(
                    in: NSRange(location: 0, length: (source as NSString).length),
                    with: result.text
                )
            }
            textView.setSelectedRange(result.selectedRange)
            restyleInPlace(textView: textView, fontSize: fontSize, editorBackground: editorBackground)
        }
        #else
        NoteUndoRegistration.perform(on: textView.undoManager) {
            if source != result.text {
                textView.text = result.text
            }
            textView.selectedRange = result.selectedRange
            restyleInPlace(textView: textView, fontSize: fontSize, editorBackground: editorBackground)
        }
        #endif

        return (result.text, result.selectedRange)
    }

    #if os(macOS)
    static func restyleInPlace(textView: NSTextView, fontSize: CGFloat, editorBackground: Color) {
        if textView.textStorage == nil { return }
        let storage = textView.textStorage!
        let selected = textView.selectedRange()
        NoteUndoRegistration.perform(on: textView.undoManager) {
            storage.beginEditing()
            WikilinkEditorSupport.restyleInPlace(
                storage,
                selectedRange: selected,
                fontSize: fontSize,
                hiddenDelimiterOn: editorBackground
            )
            storage.endEditing()
            if textView.selectedRange() != selected {
                textView.setSelectedRange(selected)
            }
        }
    }
    #else
    static func restyleInPlace(textView: UITextView, fontSize: CGFloat, editorBackground: Color) {
        let storage = textView.textStorage
        let selected = textView.selectedRange
        NoteUndoRegistration.perform(on: textView.undoManager) {
            storage.beginEditing()
            WikilinkEditorSupport.restyleInPlace(
                storage,
                selectedRange: selected,
                fontSize: fontSize,
                hiddenDelimiterOn: editorBackground
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

final class CanvasNoteTextContainerView: NSView {
    let scrollView: NSScrollView

    var textView: NoteEditingNSTextView {
        scrollView.documentView as! NoteEditingNSTextView
    }

    init(textView: NoteEditingNSTextView) {
        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
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
        if let textView = scrollView.documentView as? NSTextView {
            textView.frame = scrollView.contentView.bounds
        }
    }
}

final class NoteEditingNSTextView: NSTextView {
    weak var editingDelegate: NoteEditingTextViewDelegate?

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
}

private struct NoteBodyTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var caretRect: CGRect
    var isFocused: FocusState<Bool>.Binding
    var fontSize: CGFloat
    var embeddedInCanvas: Bool
    var containerSize: CGSize?
    var editorBackground: Color
    var onSelectionChange: () -> Void
    var onSuggestKey: (WikilinkSuggestKey) -> Bool
    var onTextEdited: ((String, Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let textView = NoteEditingNSTextView()
        textView.editingDelegate = context.coordinator
        configure(textView: textView, coordinator: context.coordinator)

        if embeddedInCanvas {
            let container = CanvasNoteTextContainerView(textView: textView)
            context.coordinator.attach(textView: textView)
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
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NoteEditingNSTextViewDelegate {
        var parent: NoteBodyTextViewRepresentable
        weak var textView: NoteEditingNSTextView?
        private var isApplyingProgrammaticChange = false

        init(parent: NoteBodyTextViewRepresentable) {
            self.parent = parent
        }

        func attach(textView: NoteEditingNSTextView) {
            self.textView = textView
        }

        func noteEditingTextView(_ textView: NoteEditingNSTextView, apply action: MarkdownEditAction) {
            guard let textView = self.textView else { return }
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.applyMarkdownEdit(
                action,
                textView: textView,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground
            )
            isApplyingProgrammaticChange = false
            Task { @MainActor in
                parent.text = updates.text
                parent.selectedRange = updates.selectedRange
                updateCaretRect(for: textView)
                parent.onSelectionChange()
                parent.onTextEdited?(updates.text, false)
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
                    hiddenDelimiterOn: parent.editorBackground
                )
                textView.textStorage?.setAttributedString(styled)
                textView.setSelectedRange(clampedRange(selectedRange, in: content))
            }
            updateCaretRect(for: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingProgrammaticChange else { return }
            restyle(textView)
            let newText = textView.string
            let newRange = textView.selectedRange()
            let fromTextUndo = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
            Task { @MainActor in
                parent.text = newText
                parent.selectedRange = newRange
                updateCaretRect(for: textView)
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
                return parent.onSuggestKey(.down)
            case #selector(NSResponder.insertNewline(_:)):
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
                editorBackground: parent.editorBackground
            )
        }

        private func updateCaretRect(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            let selected = textView.selectedRange()
            let glyphRange = layoutManager.glyphRange(forCharacterRange: selected, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height
            Task { @MainActor in
                parent.caretRect = rect
            }
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
}

private struct NoteBodyTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var caretRect: CGRect
    var isFocused: FocusState<Bool>.Binding
    var fontSize: CGFloat
    var embeddedInCanvas: Bool
    var containerSize: CGSize?
    var editorBackground: Color
    var onSelectionChange: () -> Void
    var onSuggestKey: (WikilinkSuggestKey) -> Bool
    var onTextEdited: ((String, Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> NoteEditingUITextView {
        let textView = NoteEditingUITextView()
        textView.editingDelegate = context.coordinator
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = UIColor(AppColors.textPrimary)
        textView.isScrollEnabled = embeddedInCanvas
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        context.coordinator.attach(textView: textView)
        context.coordinator.applyContent(text, selectedRange: selectedRange, to: textView)
        return textView
    }

    func updateUIView(_ textView: NoteEditingUITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncIfNeeded(text: text, selectedRange: selectedRange, in: textView)
        if let containerSize, embeddedInCanvas, containerSize.width > 1, containerSize.height > 1 {
            textView.bounds.size = containerSize
        }
        if isFocused.wrappedValue, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, NoteEditingUITextViewDelegate {
        var parent: NoteBodyTextViewRepresentable
        weak var textView: NoteEditingUITextView?
        private var isApplyingProgrammaticChange = false

        init(parent: NoteBodyTextViewRepresentable) {
            self.parent = parent
        }

        func attach(textView: NoteEditingUITextView) {
            self.textView = textView
        }

        func noteEditingTextView(_ textView: NoteEditingUITextView, apply action: MarkdownEditAction) {
            isApplyingProgrammaticChange = true
            let updates = NoteTextEditingCoordinatorSupport.applyMarkdownEdit(
                action,
                textView: textView,
                fontSize: parent.fontSize,
                editorBackground: parent.editorBackground
            )
            isApplyingProgrammaticChange = false
            Task { @MainActor in
                parent.text = updates.text
                parent.selectedRange = updates.selectedRange
                updateCaretRect(for: textView)
                parent.onSelectionChange()
                parent.onTextEdited?(updates.text, false)
            }
        }

        func noteTextViewDidApplyEdit(_ textView: AnyObject) {}

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
                    hiddenDelimiterOn: parent.editorBackground
                )
                textView.selectedRange = clampedRange(selectedRange, in: content)
            }
            updateCaretRect(for: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            restyle(textView)
            let newText = textView.text ?? ""
            let newRange = textView.selectedRange
            let fromTextUndo = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
            Task { @MainActor in
                parent.text = newText
                parent.selectedRange = newRange
                updateCaretRect(for: textView)
                parent.onSelectionChange()
                parent.onTextEdited?(newText, fromTextUndo)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            let newRange = textView.selectedRange
            restyle(textView)
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
                editorBackground: parent.editorBackground
            )
        }

        private func updateCaretRect(for textView: UITextView) {
            guard let range = textView.selectedTextRange else { return }
            let rect = textView.caretRect(for: range.end)
            Task { @MainActor in
                parent.caretRect = rect
            }
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
