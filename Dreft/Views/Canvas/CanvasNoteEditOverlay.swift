import SwiftUI

/// Screen-space note editor for canvas cards.
/// AppKit text views cannot receive clicks inside a scaled canvas card, so editing
/// happens in this overlay aligned to the card's screen rect (same pattern as the floating toolbar).
struct CanvasNoteEditOverlay: View {
    let initialText: String
    let cardSize: CGSize
    let colorHex: String?
    let files: [WorkspaceFileEntry]
    var onTextEdited: (String, Bool) -> Void
    var onDismiss: () -> Void

    @State private var draftText: String
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var caretRect = CGRect.zero
    @State private var suggestIndex = 0
    @FocusState private var isFocused: Bool

    #if os(iOS)
    var toolbarBridge: NoteFormattingToolbarBridge?
    #endif

    init(
        initialText: String,
        cardSize: CGSize,
        colorHex: String?,
        files: [WorkspaceFileEntry],
        onTextEdited: @escaping (String, Bool) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.initialText = initialText
        self.cardSize = cardSize
        self.colorHex = colorHex
        self.files = files
        self.onTextEdited = onTextEdited
        self.onDismiss = onDismiss
        #if os(iOS)
        self.toolbarBridge = nil
        #endif
        _draftText = State(initialValue: initialText)
    }

    #if os(iOS)
    init(
        initialText: String,
        cardSize: CGSize,
        colorHex: String?,
        files: [WorkspaceFileEntry],
        onTextEdited: @escaping (String, Bool) -> Void,
        onDismiss: @escaping () -> Void,
        toolbarBridge: NoteFormattingToolbarBridge?
    ) {
        self.initialText = initialText
        self.cardSize = cardSize
        self.colorHex = colorHex
        self.files = files
        self.onTextEdited = onTextEdited
        self.onDismiss = onDismiss
        self.toolbarBridge = toolbarBridge
        _draftText = State(initialValue: initialText)
    }
    #endif

    private var cardColor: Color? {
        guard let colorHex else { return nil }
        return Color(hexString: colorHex)
    }

    var body: some View {
        Group {
            #if os(iOS)
            NoteBodyTextView(
                text: $draftText,
                selectedRange: $selectedRange,
                caretRect: $caretRect,
                isFocused: $isFocused,
                files: files,
                suggestSelectedIndex: $suggestIndex,
                fontSize: 13,
                embeddedInCanvas: true,
                editorBackground: AppColors.noteCardBackground,
                onTextEdited: onTextEdited,
                toolbarBridge: toolbarBridge
            )
            #else
            NoteBodyTextView(
                text: $draftText,
                selectedRange: $selectedRange,
                caretRect: $caretRect,
                isFocused: $isFocused,
                files: files,
                suggestSelectedIndex: $suggestIndex,
                fontSize: 13,
                embeddedInCanvas: true,
                editorBackground: AppColors.noteCardBackground,
                onTextEdited: onTextEdited
            )
            #endif
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
        .background(
            ZStack {
                AppColors.noteCardBackground
                if let cardColor { cardColor.opacity(0.08) }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(cardColor ?? AppColors.selectionStroke, lineWidth: 3)
        )
        .onAppear {
            draftText = initialText
            Task { @MainActor in
                isFocused = true
            }
        }
        .onChange(of: initialText) { _, newValue in
            if draftText != newValue {
                draftText = newValue
            }
        }
        .onDisappear {
            #if os(iOS)
            toolbarBridge?.dismissKeyboard()
            #endif
        }
        #if os(macOS)
        .onExitCommand {
            onTextEdited(draftText, false)
            onDismiss()
        }
        #endif
    }
}
