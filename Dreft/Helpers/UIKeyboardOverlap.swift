#if os(iOS)
import UIKit

/// Keyboard overlap helpers that use the key window / target view — not full-screen bounds
/// (fixes Split View, Stage Manager, and rotation edge cases).
enum UIKeyboardOverlap {
    /// How far the keyboard covers the bottom of `view`, in points.
    static func overlap(keyboardFrameEnd: CGRect, relativeTo view: UIView) -> CGFloat {
        guard keyboardFrameEnd.height > 0.5 else { return 0 }
        guard let window = view.window else {
            return screenOverlap(keyboardFrameEnd: keyboardFrameEnd)
        }
        let keyboardInWindow = window.convert(keyboardFrameEnd, from: nil)
        let viewInWindow = view.convert(view.bounds, to: window)
        return max(0, viewInWindow.maxY - keyboardInWindow.minY)
    }

    /// Overlap from the bottom of the key window — for canvas-level keyboard avoidance.
    static func overlapInKeyWindow(keyboardFrameEnd: CGRect) -> CGFloat {
        guard keyboardFrameEnd.height > 0.5 else { return 0 }
        guard let window = keyWindow else {
            return screenOverlap(keyboardFrameEnd: keyboardFrameEnd)
        }
        let keyboardInWindow = window.convert(keyboardFrameEnd, from: nil)
        return max(0, window.bounds.height - keyboardInWindow.minY)
    }

    private static func screenOverlap(keyboardFrameEnd: CGRect) -> CGFloat {
        max(0, UIScreen.main.bounds.maxY - keyboardFrameEnd.minY)
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
#endif
