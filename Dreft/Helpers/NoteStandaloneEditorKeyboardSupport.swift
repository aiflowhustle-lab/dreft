#if os(iOS)
import Combine
import UIKit

/// Keeps standalone iPad note editors scrolled above the keyboard + formatting accessory.
enum NoteStandaloneEditorKeyboardSupport {
    static func accessoryHeight(for textView: UITextView) -> CGFloat {
        // Toolbar lives in a SwiftUI overlay now; still reserve the same height
        // so caret/scroll stay above it when the software keyboard is up.
        _ = textView
        guard UIDevice.current.userInterfaceIdiom == .pad else { return 0 }
        return NoteFormattingToolbarAccessoryContainer.preferredHeight
    }

    static func applyContentInsets(to textView: UITextView, keyboardOverlap: CGFloat) {
        let accessory = accessoryHeight(for: textView)
        let bottomInset = max(0, keyboardOverlap + accessory)
        guard textView.contentInset.bottom != bottomInset
            || textView.verticalScrollIndicatorInsets.bottom != bottomInset else { return }

        textView.contentInset.bottom = bottomInset
        textView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    static func scrollSelectionIntoView(_ textView: UITextView, fontSize: CGFloat) {
        guard textView.isScrollEnabled else { return }
        textView.layoutIfNeeded()
        textView.scrollRangeToVisible(textView.selectedRange)
        CanvasNoteEditorScrollSupport.scrollCaretIntoViewIfNeeded(textView, fontSize: fontSize)
    }
}

@MainActor
final class NoteStandaloneEditorKeyboardObserver {
    private var cancellables = Set<AnyCancellable>()
    private weak var textView: UITextView?
    private var fontSize: CGFloat = WikilinkEditorSupport.bodyFontSize
    private var onOverlapChange: ((CGFloat) -> Void)?

    func attach(
        to textView: UITextView,
        fontSize: CGFloat,
        onOverlapChange: ((CGFloat) -> Void)? = nil
    ) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        self.textView = textView
        self.fontSize = fontSize
        self.onOverlapChange = onOverlapChange
        cancellables.removeAll()

        let names: [Notification.Name] = [
            UIResponder.keyboardWillShowNotification,
            UIResponder.keyboardWillHideNotification,
            UIResponder.keyboardWillChangeFrameNotification,
        ]

        for name in names {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    self?.handleKeyboardNotification(notification)
                }
                .store(in: &cancellables)
        }
    }

    func detach() {
        cancellables.removeAll()
        if let textView {
            NoteStandaloneEditorKeyboardSupport.applyContentInsets(to: textView, keyboardOverlap: 0)
        }
        textView = nil
        onOverlapChange?(0)
        onOverlapChange = nil
    }

    private func handleKeyboardNotification(_ notification: Notification) {
        guard let textView else { return }

        let overlap: CGFloat
        if notification.name == UIResponder.keyboardWillHideNotification {
            overlap = 0
        } else if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            overlap = UIKeyboardOverlap.overlap(keyboardFrameEnd: frame, relativeTo: textView)
        } else {
            overlap = 0
        }

        NoteStandaloneEditorKeyboardSupport.applyContentInsets(to: textView, keyboardOverlap: overlap)
        onOverlapChange?(overlap)
        NoteStandaloneEditorKeyboardSupport.scrollSelectionIntoView(textView, fontSize: fontSize)
    }
}
#endif
