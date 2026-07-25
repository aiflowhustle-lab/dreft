#if os(iOS)
import Combine
import SwiftUI
import UIKit

@MainActor
final class KeyboardHeightObserver: ObservableObject {
    @Published private(set) var height: CGFloat = 0
    @Published private(set) var isVisible = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        let show = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        let hide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        let change = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)

        show.merge(with: change)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.applyFrame(from: notification, visible: true)
            }
            .store(in: &cancellables)

        hide
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.applyFrame(from: notification, visible: false)
            }
            .store(in: &cancellables)
    }

    private func applyFrame(from notification: Notification, visible: Bool) {
        let nextHeight: CGFloat
        let nextVisible: Bool

        if visible,
           let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let screenHeight = UIScreen.main.bounds.height
            let overlap = max(0, screenHeight - frame.origin.y)
            nextHeight = overlap
            nextVisible = overlap > 0
        } else {
            nextHeight = 0
            nextVisible = false
        }

        guard height != nextHeight || isVisible != nextVisible else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.height != nextHeight { self.height = nextHeight }
            if self.isVisible != nextVisible { self.isVisible = nextVisible }
        }
    }
}

struct NoteIPadFormattingToolbar: View {
    var canUndo: Bool
    var canRedo: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onAction: (MarkdownEditAction) -> Void
    var onDismissKeyboard: () -> Void

    var body: some View {
        CanvasFloatingToolbarChrome.bottomBar {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    toolbarButton("arrow.uturn.backward", enabled: canUndo, action: onUndo)
                    toolbarButton("arrow.uturn.forward", enabled: canRedo, action: onRedo)

                    toolbarDivider

                    textButton("[ ]") { onAction(.wikilink) }
                    toolbarButton("doc.plaintext") { onAction(.wikilink) }
                    toolbarButton("tag") { onAction(.tag) }
                    toolbarButton("paperclip") { }
                        .disabled(true)
                        .opacity(0.32)

                    toolbarDivider

                    headingMenu
                    textButton("B", weight: .bold) { onAction(.bold) }
                    textButton("I", weight: .regular) { onAction(.italic) }
                    textButton("S", weight: .regular) { onAction(.strikethrough) }
                    textButton("&", weight: .semibold) { onAction(.highlight) }
                    toolbarButton("chevron.left.forwardslash.chevron.right") { onAction(.inlineCode) }
                    toolbarButton("quote.opening") { onAction(.quote) }

                    toolbarDivider

                    toolbarButton("link") { onAction(.externalLink) }
                    toolbarButton("list.bullet") { onAction(.bulletList) }
                    toolbarButton("list.number") { onAction(.numberedList) }
                    toolbarButton("checklist") { onAction(.taskList) }
                    toolbarButton("decrease.indent") { onAction(.outdent) }
                    toolbarButton("increase.indent") { onAction(.indent) }

                    toolbarDivider

                    moreMenu
                    toolbarButton("keyboard.chevron.compact.down", action: onDismissKeyboard)
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var headingMenu: some View {
        Menu {
            Button("Heading 1") { onAction(.heading1) }
            Button("Heading 2") { onAction(.heading2) }
            Button("Heading 3") { onAction(.heading3) }
            Button("Heading 4") { onAction(.heading4) }
            Button("Heading 5") { onAction(.heading5) }
            Button("Heading 6") { onAction(.heading6) }
            Divider()
            Button("Body") { onAction(.body) }
        } label: {
            textLabel("H", weight: .semibold)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }

    private var moreMenu: some View {
        Menu {
            Button("Code block") { onAction(.codeBlock) }
            Button("Horizontal rule") { onAction(.horizontalRule) }
            Button("Callout") { onAction(.callout) }
            Divider()
            Button("Clear formatting") { onAction(.clearFormatting) }
        } label: {
            Image(systemName: "wrench")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 6)
    }

    private func toolbarButton(
        _ systemName: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(enabled ? AppColors.textSecondary : AppColors.textMuted)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func textButton(
        _ label: String,
        weight: Font.Weight = .medium,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            textLabel(label, weight: weight)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func textLabel(_ text: String, weight: Font.Weight) -> some View {
        Text(text)
            .font(.system(size: 15, weight: weight, design: .rounded))
            .foregroundStyle(AppColors.textSecondary)
    }
}

private struct NoteIPadFormattingToolbarHost: View {
    @ObservedObject var bridge: NoteFormattingToolbarBridge

    var body: some View {
        NoteIPadFormattingToolbar(
            canUndo: bridge.canUndo,
            canRedo: bridge.canRedo,
            onUndo: { bridge.undo() },
            onRedo: { bridge.redo() },
            onAction: { bridge.applyAction?($0) },
            onDismissKeyboard: { bridge.dismissKeyboard() }
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }
}

final class NoteFormattingToolbarAccessoryContainer: UIView {
    static let preferredHeight: CGFloat = 48

    private let bridge: NoteFormattingToolbarBridge
    private var hostingController: UIHostingController<NoteIPadFormattingToolbarHost>?

    init(bridge: NoteFormattingToolbarBridge) {
        self.bridge = bridge
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.preferredHeight))
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear
        installHostingController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    private func installHostingController() {
        let host = UIHostingController(rootView: NoteIPadFormattingToolbarHost(bridge: bridge))
        hostingController = host
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

#endif
