import CoreGraphics

struct CanvasNoteScrollConsumption: Equatable {
    var consumed: Bool

    static let none = CanvasNoteScrollConsumption(consumed: false)
    static let absorbed = CanvasNoteScrollConsumption(consumed: true)
}

/// Routes wheel / trackpad deltas into the active note-card scroller (preview or edit).
enum CanvasNoteCardScrollBridge {
    private static var ownerID: String?
    static var applyScrollDelta: ((CGSize) -> CanvasNoteScrollConsumption)?

    static func register(owner: String, handler: @escaping (CGSize) -> CanvasNoteScrollConsumption) {
        ownerID = owner
        applyScrollDelta = handler
    }

    static func unregister(owner: String) {
        guard ownerID == owner else { return }
        ownerID = nil
        applyScrollDelta = nil
    }

    @discardableResult
    static func apply(_ delta: CGSize) -> CanvasNoteScrollConsumption {
        applyScrollDelta?(delta) ?? .none
    }
}

enum CanvasNoteCardScrollMath {
    static func clampedOffset(
        current: CGFloat,
        delta: CGFloat,
        maxOffset: CGFloat
    ) -> (offset: CGFloat, overflow: CGFloat) {
        guard maxOffset > 0 else {
            return (0, delta)
        }
        let proposed = current - delta
        let appliedOffset = min(max(proposed, 0), maxOffset)
        // Remaining scroll delta that could not be applied inside the note card.
        let overflow = delta - (current - appliedOffset)
        return (appliedOffset, overflow)
    }

    static func clampedOffset(
        current: CGPoint,
        delta: CGSize,
        maxOffset: CGPoint
    ) -> (offset: CGPoint, overflow: CGSize) {
        let x = clampedOffset(current: current.x, delta: delta.width, maxOffset: max(0, maxOffset.x))
        let y = clampedOffset(current: current.y, delta: delta.height, maxOffset: max(0, maxOffset.y))
        return (
            CGPoint(x: x.offset, y: y.offset),
            CGSize(width: x.overflow, height: y.overflow)
        )
    }
}

#if os(macOS)
import AppKit

extension CanvasNoteCardScrollBridge {
    static func scroll(_ scrollView: NSScrollView, by delta: CGSize) -> CanvasNoteScrollConsumption {
        guard let documentView = scrollView.documentView else { return .none }

        let visible = scrollView.contentView.bounds.size
        let maxOffset = CGPoint(
            x: max(0, documentView.frame.width - visible.width),
            y: max(0, documentView.frame.height - visible.height)
        )
        if maxOffset.x <= 0.5 && maxOffset.y <= 0.5 {
            return .absorbed
        }

        let current = scrollView.contentView.bounds.origin
        let clamped = CanvasNoteCardScrollMath.clampedOffset(
            current: current,
            delta: delta,
            maxOffset: maxOffset
        )

        if clamped.offset != current {
            scrollView.contentView.scroll(to: clamped.offset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        return .absorbed
    }
}
#endif

#if os(iOS)
import UIKit

extension CanvasNoteCardScrollBridge {
    static func scroll(_ scrollView: UIScrollView, by delta: CGSize) -> CanvasNoteScrollConsumption {
        let maxOffset = CGPoint(
            x: max(0, scrollView.contentSize.width - scrollView.bounds.width),
            y: max(0, scrollView.contentSize.height - scrollView.bounds.height)
        )
        if maxOffset.x <= 0.5 && maxOffset.y <= 0.5 {
            return .absorbed
        }

        let clamped = CanvasNoteCardScrollMath.clampedOffset(
            current: scrollView.contentOffset,
            delta: delta,
            maxOffset: maxOffset
        )

        if clamped.offset != scrollView.contentOffset {
            scrollView.setContentOffset(clamped.offset, animated: false)
        }

        return .absorbed
    }

    static func scroll(_ textView: UITextView, by delta: CGSize) -> CanvasNoteScrollConsumption {
        scroll(textView as UIScrollView, by: delta)
    }
}
#endif
