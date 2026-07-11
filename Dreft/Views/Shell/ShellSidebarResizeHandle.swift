import SwiftUI
#if os(macOS)
import AppKit
#endif

enum SidebarResizeDividerMetrics {
    static let lineWidth: CGFloat = 2.5
}

struct ShellSidebarResizeHandle: View {
    @Binding var width: CGFloat
    var onResizeBegan: () -> Void = {}
    var onCommit: () -> Void = {}

    var body: some View {
        #if os(macOS)
        ShellSidebarResizeHandleMac(
            width: $width,
            onResizeBegan: onResizeBegan,
            onCommit: onCommit
        )
        .frame(width: SidebarResizeDividerMetrics.lineWidth)
        #else
        ShellSidebarResizeHandleIOS(
            width: $width,
            onResizeBegan: onResizeBegan,
            onCommit: onCommit
        )
        #endif
    }
}

#if os(macOS)
private struct ShellSidebarResizeHandleMac: NSViewRepresentable {
    @Binding var width: CGFloat
    var onResizeBegan: () -> Void
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            width: $width,
            onResizeBegan: onResizeBegan,
            onCommit: onCommit
        )
    }

    func makeNSView(context: Context) -> SidebarResizeDividerView {
        let view = SidebarResizeDividerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: SidebarResizeDividerView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.width = $width
        context.coordinator.onResizeBegan = onResizeBegan
        context.coordinator.onCommit = onCommit
        nsView.syncHoverState(for: nsView.window?.mouseLocationOutsideOfEventStream)
    }

    final class Coordinator: NSObject {
        var width: Binding<CGFloat>
        var onResizeBegan: () -> Void
        var onCommit: () -> Void

        var dragStartX: CGFloat = 0
        var dragStartWidth: CGFloat = 0
        var isDragging = false

        init(
            width: Binding<CGFloat>,
            onResizeBegan: @escaping () -> Void,
            onCommit: @escaping () -> Void
        ) {
            self.width = width
            self.onResizeBegan = onResizeBegan
            self.onCommit = onCommit
        }

        func applyDrag(locationInWindowX: CGFloat) {
            let delta = locationInWindowX - dragStartX
            width.wrappedValue = SidebarLayout.clamped(dragStartWidth + delta)
        }
    }
}

private final class SidebarResizeDividerView: NSView {
    weak var coordinator: ShellSidebarResizeHandleMac.Coordinator?
    private var isLineHovered = false
    private var trackingArea: NSTrackingArea?

    private let lineWidth = SidebarResizeDividerMetrics.lineWidth
    private let cursorProximity: CGFloat = SidebarResizeDividerMetrics.lineWidth / 2 + 1.5
    private let dragProximity: CGFloat = SidebarResizeDividerMetrics.lineWidth / 2 + 4

    override var isOpaque: Bool { false }

    private var lineCenterX: CGFloat { bounds.maxX - lineWidth / 2 }

    private func isNearLine(_ localX: CGFloat, proximity: CGFloat) -> Bool {
        abs(localX - lineCenterX) <= proximity
    }

    private var cursorRect: NSRect {
        NSRect(
            x: lineCenterX - cursorProximity,
            y: bounds.minY,
            width: cursorProximity * 2,
            height: bounds.height
        )
    }

    private var dragRect: NSRect {
        NSRect(
            x: lineCenterX - dragProximity,
            y: bounds.minY,
            width: dragProximity + lineWidth / 2,
            height: bounds.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isActive = isLineHovered || (coordinator?.isDragging ?? false)
        let color = isActive ? NSColor(AppColors.resizeEdgeHandle) : NSColor(AppColors.borderSubtle)
        color.setFill()

        let lineRect = NSRect(
            x: bounds.maxX - lineWidth,
            y: bounds.minY,
            width: lineWidth,
            height: bounds.height
        )
        NSBezierPath(rect: lineRect).fill()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard bounds.height > 0 else { return }

        if coordinator?.isDragging == true {
            addCursorRect(dragRect, cursor: .resizeLeftRight)
        } else {
            addCursorRect(cursorRect, cursor: .resizeLeftRight)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        guard bounds.height > 0 else { return }

        let area = NSTrackingArea(
            rect: cursorRect,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .enabledDuringMouseDrag],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.height > 0, dragRect.contains(point) else { return nil }
        return self
    }

    override func mouseMoved(with event: NSEvent) {
        syncHoverState(for: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        syncHoverState(for: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        setLineHovered(false)
        refreshCursor()
    }

    func syncHoverState(for windowLocation: NSPoint?) {
        guard let windowLocation else {
            setLineHovered(false)
            refreshCursor()
            return
        }

        let local = convert(windowLocation, from: nil)
        let nearLine = dragRect.contains(local) && isNearLine(local.x, proximity: cursorProximity)
        setLineHovered(nearLine)
        refreshCursor()
    }

    private func setLineHovered(_ hovered: Bool) {
        guard hovered != isLineHovered else { return }
        isLineHovered = hovered
        needsDisplay = true
    }

    private func refreshCursor() {
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard isNearLine(local.x, proximity: dragProximity), let coordinator else { return }

        setLineHovered(true)
        refreshCursor()
        coordinator.dragStartX = event.locationInWindow.x
        coordinator.dragStartWidth = coordinator.width.wrappedValue
        coordinator.isDragging = true
        coordinator.onResizeBegan()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let coordinator, coordinator.isDragging else { return }
        coordinator.applyDrag(locationInWindowX: event.locationInWindow.x)
        refreshCursor()
    }

    override func mouseUp(with event: NSEvent) {
        guard let coordinator, coordinator.isDragging else { return }
        coordinator.isDragging = false
        coordinator.onCommit()
        syncHoverState(for: event.locationInWindow)
    }
}
#else
private struct ShellSidebarResizeHandleIOS: View {
    @Binding var width: CGFloat
    var onResizeBegan: () -> Void
    var onCommit: () -> Void

    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(width: SidebarResizeDividerMetrics.lineWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                            onResizeBegan()
                        }
                        guard let start = dragStartWidth else { return }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            width = SidebarLayout.clamped(start + value.translation.width)
                        }
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        onCommit()
                    }
            )
    }
}
#endif
