#if os(iOS)
import Combine
import UIKit

/// Keeps standalone iPad note editors scrolled above the keyboard + formatting accessory.
enum NoteStandaloneEditorKeyboardSupport {
    static func accessoryHeight(for textView: UITextView) -> CGFloat {
        textView.inputAccessoryView?.bounds.height
            ?? NoteFormattingToolbarAccessoryContainer.preferredHeight
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

    func attach(to textView: UITextView, fontSize: CGFloat) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        self.textView = textView
        self.fontSize = fontSize
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
    }

    private func handleKeyboardNotification(_ notification: Notification) {
        guard let textView else { return }

        let overlap: CGFloat
        if notification.name == UIResponder.keyboardWillHideNotification {
            overlap = 0
        } else if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let screenHeight = UIScreen.main.bounds.height
            overlap = max(0, screenHeight - frame.origin.y)
        } else {
            overlap = 0
        }

        NoteStandaloneEditorKeyboardSupport.applyContentInsets(to: textView, keyboardOverlap: overlap)
        NoteStandaloneEditorKeyboardSupport.scrollSelectionIntoView(textView, fontSize: fontSize)
    }
}
#endif
