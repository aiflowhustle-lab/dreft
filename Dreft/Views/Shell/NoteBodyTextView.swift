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

struct NoteBodyTextView: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var caretRect: CGRect
    var isFocused: FocusState<Bool>.Binding
    let files: [WorkspaceFileEntry]
    @Binding var suggestSelectedIndex: Int

    @State private var activeQuery: WikilinkActiveQuery?

    private var suggestions: [WorkspaceFileEntry] {
        guard let activeQuery else { return [] }
        return WikilinkSuggestSearch.results(matching: activeQuery.query, in: files)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            NoteBodyTextViewRepresentable(
                text: $text,
                selectedRange: $selectedRange,
                caretRect: $caretRect,
                isFocused: isFocused,
                onSelectionChange: refreshActiveQuery,
                onSuggestKey: handleSuggestKey
            )
            .frame(minHeight: 520)

            if activeQuery != nil, !suggestions.isEmpty {
                WikilinkSuggestPopover(
                    results: suggestions,
                    selectedIndex: suggestSelectedIndex
                )
                .offset(x: caretRect.minX, y: caretRect.maxY + 6)
                .zIndex(20)
            }
        }
        .onChange(of: text) { _, _ in refreshActiveQuery() }
    }

    private func refreshActiveQuery() {
        let cursor = selectedRange.location + selectedRange.length
        let query = WikilinkEditorSupport.activeQuery(in: text, cursor: cursor)
        if query != activeQuery {
            activeQuery = query
            if query != nil {
                suggestSelectedIndex = 0
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

#if os(macOS)

private struct NoteBodyTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var caretRect: CGRect
    var isFocused: FocusState<Bool>.Binding
    var onSelectionChange: () -> Void
    var onSuggestKey: (WikilinkSuggestKey) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
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
        textView.font = .systemFont(ofSize: WikilinkEditorSupport.bodyFontSize)
        textView.textColor = NSColor(AppColors.textPrimary)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        context.coordinator.attach(textView: textView)
        context.coordinator.applyContent(text, selectedRange: selectedRange, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        context.coordinator.syncIfNeeded(text: text, selectedRange: selectedRange, in: textView)

        if isFocused.wrappedValue, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteBodyTextViewRepresentable
        weak var textView: NSTextView?
        private var isApplyingProgrammaticChange = false

        init(parent: NoteBodyTextViewRepresentable) {
            self.parent = parent
        }

        func attach(textView: NSTextView) {
            self.textView = textView
        }

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

            let styled = WikilinkEditorSupport.attributedString(for: content, selectedRange: selectedRange)
            textView.textStorage?.setAttributedString(styled)
            textView.setSelectedRange(clampedRange(selectedRange, in: content))
            updateCaretRect(for: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingProgrammaticChange else { return }
            restyle(textView)
            parent.text = textView.string
            parent.selectedRange = textView.selectedRange()
            updateCaretRect(for: textView)
            parent.onSelectionChange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingProgrammaticChange else { return }
            parent.selectedRange = textView.selectedRange()
            restyle(textView)
            updateCaretRect(for: textView)
            parent.onSelectionChange()
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
            let selected = textView.selectedRange()
            let plain = textView.string
            let styled = WikilinkEditorSupport.attributedString(for: plain, selectedRange: selected)
            isApplyingProgrammaticChange = true
            textView.textStorage?.setAttributedString(styled)
            textView.setSelectedRange(selected)
            isApplyingProgrammaticChange = false
        }

        private func updateCaretRect(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            let selected = textView.selectedRange()
            let glyphRange = layoutManager.glyphRange(forCharacterRange: selected, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height
            parent.caretRect = rect
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

private struct NoteBodyTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var caretRect: CGRect
    var isFocused: FocusState<Bool>.Binding
    var onSelectionChange: () -> Void
    var onSuggestKey: (WikilinkSuggestKey) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: WikilinkEditorSupport.bodyFontSize)
        textView.textColor = UIColor(AppColors.textPrimary)
        textView.isScrollEnabled = false
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

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncIfNeeded(text: text, selectedRange: selectedRange, in: textView)
        if isFocused.wrappedValue, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteBodyTextViewRepresentable
        weak var textView: UITextView?
        private var isApplyingProgrammaticChange = false

        init(parent: NoteBodyTextViewRepresentable) {
            self.parent = parent
        }

        func attach(textView: UITextView) {
            self.textView = textView
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

            textView.attributedText = WikilinkEditorSupport.attributedString(for: content, selectedRange: selectedRange)
            textView.selectedRange = clampedRange(selectedRange, in: content)
            updateCaretRect(for: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            restyle(textView)
            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
            updateCaretRect(for: textView)
            parent.onSelectionChange()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            parent.selectedRange = textView.selectedRange
            restyle(textView)
            updateCaretRect(for: textView)
            parent.onSelectionChange()
        }

        private func restyle(_ textView: UITextView) {
            let selected = textView.selectedRange
            let plain = textView.text ?? ""
            isApplyingProgrammaticChange = true
            textView.attributedText = WikilinkEditorSupport.attributedString(for: plain, selectedRange: selected)
            textView.selectedRange = selected
            isApplyingProgrammaticChange = false
        }

        private func updateCaretRect(for textView: UITextView) {
            guard let range = textView.selectedTextRange else { return }
            parent.caretRect = textView.caretRect(for: range)
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
