import Combine
import SwiftUI

#if os(iOS)
import UIKit

struct NoteEditorAccessoryStatus: Equatable {
    var saveLabel: String?
    var backlinkCount: Int
    var wordCount: Int
    var characterCount: Int
}

@MainActor
final class NoteFormattingToolbarBridge: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var isTextEditingActive = false
    @Published var accessoryStatus: NoteEditorAccessoryStatus?

    weak var textView: UITextView?
    var applyAction: ((MarkdownEditAction) -> Void)?
    var onInsertAttachment: (() -> Void)?
    var insertSnippetHandler: ((String) -> Void)?
    private var refreshScheduled = false
    private var accessoryContainer: NoteFormattingToolbarAccessoryContainer?

    func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.publishStateIfNeeded()
        }
    }

    private func publishStateIfNeeded() {
        let nextUndo = textView?.undoManager?.canUndo ?? false
        let nextRedo = textView?.undoManager?.canRedo ?? false
        let nextEditing = textView?.isFirstResponder ?? false
        if canUndo != nextUndo { canUndo = nextUndo }
        if canRedo != nextRedo { canRedo = nextRedo }
        if isTextEditingActive != nextEditing { isTextEditingActive = nextEditing }
    }

    func attachInputAccessory(to textView: UITextView) {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            clearInputAccessory(on: textView)
            return
        }

        if let noteTextView = textView as? NoteEditingUITextView {
            self.textView = noteTextView
        } else {
            self.textView = textView
        }

        let container = accessoryContainer ?? {
            let created = NoteFormattingToolbarAccessoryContainer(bridge: self)
            accessoryContainer = created
            return created
        }()

        guard textView.inputAccessoryView !== container else {
            scheduleRefresh()
            return
        }

        textView.inputAccessoryView = container
        if textView.isFirstResponder {
            textView.reloadInputViews()
        }
        scheduleRefresh()
    }

    func clearInputAccessory(on textView: UITextView) {
        let empty = UIView(frame: .zero)
        guard textView.inputAccessoryView !== empty else { return }
        textView.inputAccessoryView = empty
        if textView.isFirstResponder {
            textView.reloadInputViews()
        }
    }

    func undo() {
        textView?.undoManager?.undo()
        scheduleRefresh()
    }

    func redo() {
        textView?.undoManager?.redo()
        scheduleRefresh()
    }

    func dismissKeyboard() {
        textView?.resignFirstResponder()
        scheduleRefresh()
    }

    func detachFromEditor() {
        textView = nil
        applyAction = nil
        insertSnippetHandler = nil
        scheduleRefresh()
    }

    func requestAttachment() {
        onInsertAttachment?()
    }

    func applyFormatting(_ action: MarkdownEditAction) {
        if action == .attachment {
            requestAttachment()
            return
        }
        applyAction?(action)
        scheduleRefresh()
    }

    func insertFormattingSnippet(_ snippet: String) {
        insertSnippetHandler?(snippet)
        scheduleRefresh()
    }

    func insertSnippet(_ snippet: String) {
        insertSnippetHandler?(snippet)
        scheduleRefresh()
    }
}

#elseif os(macOS)
import AppKit

@MainActor
final class NoteFormattingToolbarBridge: ObservableObject {
    weak var textView: NSTextView?
    var onInsertAttachment: (() -> Void)?
    var insertSnippetHandler: ((String) -> Void)?

    func dismissKeyboard() {
        textView?.window?.makeFirstResponder(nil)
    }

    func requestAttachment() {
        onInsertAttachment?()
    }

    func insertSnippet(_ snippet: String) {
        insertSnippetHandler?(snippet)
    }
}

#endif
