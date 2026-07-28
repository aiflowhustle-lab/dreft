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

    private let buttonSize = CanvasFloatingToolbarChrome.keyboardAccessoryButtonSize

    var body: some View {
        HStack(spacing: 8) {
            CanvasFloatingToolbarChrome.keyboardAccessoryBar {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        toolbarButton("arrow.uturn.backward", label: "Undo", enabled: canUndo, action: onUndo)
                        toolbarButton("arrow.uturn.forward", label: "Redo", enabled: canRedo, action: onRedo)

                        wikilinkButton
                        toolbarButton("doc.plaintext", label: "Add embed") { onAction(.embed) }
                        toolbarButton("tag", label: "Add tag") { onAction(.tag) }
                        toolbarButton("paperclip", label: "Insert attachment") { onAction(.attachment) }

                        headingMenu
                        toolbarButton("bold", label: "Bold") { onAction(.bold) }
                        toolbarButton("italic", label: "Italic") { onAction(.italic) }
                        toolbarButton("strikethrough", label: "Strikethrough") { onAction(.strikethrough) }
                        toolbarButton("highlighter", label: "Highlight") { onAction(.highlight) }
                        toolbarButton("chevron.left.forwardslash.chevron.right", label: "Code") { onAction(.inlineCode) }
                        toolbarButton("text.quote", label: "Blockquote") { onAction(.quote) }

                        toolbarButton("link", label: "Insert link") { onAction(.externalLink) }
                        toolbarButton("list.bullet", label: "Bullet list") { onAction(.bulletList) }
                        toolbarButton("list.number", label: "Numbered list") { onAction(.numberedList) }
                        checkboxButton
                        toolbarButton("increase.indent", label: "Indent") { onAction(.indent) }
                        toolbarButton("decrease.indent", label: "Outdent") { onAction(.outdent) }

                        moreMenu
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            CanvasFloatingToolbarChrome.keyboardDismissButton {
                Button(action: onDismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide keyboard")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var wikilinkButton: some View {
        Button(action: { onAction(.wikilink) }) {
            Text("[[")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Circle())
        }
        .buttonStyle(ToolbarIconButtonStyle())
        .accessibilityLabel("Add internal link")
    }

    /// 4th from the right — toggles `- [ ]` / `- [x]` on the current line.
    private var checkboxButton: some View {
        Button(action: { onAction(.taskList) }) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(AppColors.textSecondary, lineWidth: 1.6)
                .frame(width: 16, height: 16)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Circle())
        }
        .buttonStyle(ToolbarIconButtonStyle())
        .accessibilityLabel("Checkbox")
    }

    private var headingMenu: some View {
        Menu {
            Button("No heading") { onAction(.body) }
            Button("Heading 1") { onAction(.heading1) }
            Button("Heading 2") { onAction(.heading2) }
            Button("Heading 3") { onAction(.heading3) }
            Button("Heading 4") { onAction(.heading4) }
            Button("Heading 5") { onAction(.heading5) }
            Button("Heading 6") { onAction(.heading6) }
        } label: {
            Image(systemName: "textformat.size")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Toggle heading")
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
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("More tools")
    }

    private func toolbarButton(
        _ systemName: String,
        label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(enabled ? AppColors.textSecondary : AppColors.textMuted)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Circle())
        }
        .buttonStyle(ToolbarIconButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

private struct ToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(configuration.isPressed ? AppColors.borderSubtle.opacity(0.55) : .clear)
            )
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
    }
}

final class NoteFormattingToolbarAccessoryContainer: UIView {
    static let preferredHeight: CGFloat = 64

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
            host.view.centerXAnchor.constraint(equalTo: centerXAnchor),
            host.view.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            host.view.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

#endif
