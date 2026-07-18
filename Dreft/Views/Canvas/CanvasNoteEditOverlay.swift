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
        _draftText = State(initialValue: initialText)
    }

    private var cardColor: Color? {
        guard let colorHex else { return nil }
        return Color(hexString: colorHex)
    }

    var body: some View {
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
        #if os(macOS)
        .onExitCommand {
            onTextEdited(draftText, false)
            onDismiss()
        }
        #endif
    }
}
