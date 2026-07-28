import SwiftUI
import UniformTypeIdentifiers

typealias NoteImageInserter = (Data, String?) -> Bool
typealias NoteImageInserterRegistrar = (NoteImageInserter?) -> Void

/// Screen-space note editor for canvas cards.
/// AppKit text views cannot receive clicks inside a scaled canvas card, so editing
/// happens in this overlay aligned to the card's screen rect (same pattern as the floating toolbar).
struct CanvasNoteEditOverlay: View {
    let initialText: String
    let cardSize: CGSize
    let colorHex: String?
    let files: [WorkspaceFileEntry]
    var vaultURL: URL?
    var fontSize: CGFloat = CanvasConstants.noteCardFontSize
    var imageCacheRevision: Int = 0
    var onTextEdited: (String, Bool) -> Void
    var onDismiss: () -> Void
    var onImageEmbedSaved: ((String) -> Void)? = nil
    var onRegisterImageInserter: NoteImageInserterRegistrar? = nil

    @State private var draftText: String
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var caretRect = CGRect.zero
    @State private var selectionRects: [CGRect] = []
    @State private var suggestIndex = 0
    @FocusState private var isFocused: Bool
    @State private var contentScrollOffset = CGPoint.zero
    @State private var scrollMetrics = CanvasNoteScrollMetrics()
    @State private var embedLayoutRevision = 0
    /// Stays enabled for the whole edit session so typing never flips the editor out of attachment mode.
    @State private var usesInlineImageEditor = false

    var toolbarBridge: NoteFormattingToolbarBridge?

    init(
        initialText: String,
        cardSize: CGSize,
        colorHex: String?,
        files: [WorkspaceFileEntry],
        vaultURL: URL? = nil,
        fontSize: CGFloat = CanvasConstants.noteCardFontSize,
        imageCacheRevision: Int = 0,
        onTextEdited: @escaping (String, Bool) -> Void,
        onDismiss: @escaping () -> Void,
        toolbarBridge: NoteFormattingToolbarBridge? = nil,
        onImageEmbedSaved: ((String) -> Void)? = nil,
        onRegisterImageInserter: NoteImageInserterRegistrar? = nil
    ) {
        self.initialText = initialText
        self.cardSize = cardSize
        self.colorHex = colorHex
        self.files = files
        self.vaultURL = vaultURL
        self.fontSize = fontSize
        self.imageCacheRevision = imageCacheRevision
        self.onTextEdited = onTextEdited
        self.onDismiss = onDismiss
        self.toolbarBridge = toolbarBridge
        self.onImageEmbedSaved = onImageEmbedSaved
        self.onRegisterImageInserter = onRegisterImageInserter
        _draftText = State(initialValue: initialText)
    }

    private var cardColor: Color? {
        guard let colorHex else { return nil }
        return Color(hexString: colorHex)
    }

    private var editorSurface: Color {
        CanvasCardColors.noteSurface(colorHex: colorHex)
    }

    private var contentWidth: CGFloat {
        max(1, cardSize.width - 16)
    }

    private var hasTaskLines: Bool {
        NoteCardTaskSupport.parsedLines(from: draftText).contains { line in
            if case .task = line { return true }
            return false
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            NoteBodyTextView(
                text: $draftText,
                selectedRange: $selectedRange,
                caretRect: $caretRect,
                selectionRects: $selectionRects,
                isFocused: $isFocused,
                files: files,
                suggestSelectedIndex: $suggestIndex,
                fontSize: fontSize,
                embeddedInCanvas: true,
                editorBackground: editorSurface,
                vaultURL: vaultURL,
                hideResolvedImageEmbeds: editorHideResolvedImageEmbeds,
                imageEmbedMaxWidth: contentWidth,
                hideTaskListMarkers: editorHideTaskListMarkers,
                onTextEdited: onTextEdited,
                toolbarBridge: toolbarBridge,
                onImageAttachmentDrop: insertImageAttachment,
                layoutRefreshToken: editorLayoutRefreshToken,
                onContentScroll: { metrics in
                    Task { @MainActor in
                        scrollMetrics = metrics
                        contentScrollOffset = metrics.offset
                    }
                }
            )

            editorChromeOverlays

            CanvasNoteCardScrollIndicator(metrics: scrollMetrics)
                .zIndex(20)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
        .background(editorSurface)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(cardColor ?? AppColors.selectionStroke, lineWidth: 3)
        )
        .onAppear(perform: handleAppear)
        .onDisappear {
            onRegisterImageInserter?(nil)
            toolbarBridge?.dismissKeyboard()
            CanvasNoteCardScrollBridge.unregister(owner: "edit")
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            var handled = false
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    handled = true
                    NoteImageDropSupport.loadData(from: provider) { data, name in
                        _ = insertImageAttachment(data, name)
                    }
                }
            }
            return handled
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

    private var editorHideResolvedImageEmbeds: Bool {
        usesInlineImageEditor
    }

    private var editorHideTaskListMarkers: Bool {
        hasTaskLines
    }

    private var editorLayoutRefreshToken: Int {
        imageCacheRevision + embedLayoutRevision
    }

    @ViewBuilder
    private var editorChromeOverlays: some View {
        if usesInlineImageEditor, isFocused {
            NoteEditingCaretOverlay(
                caretRect: caretRect,
                selectionRects: selectionRects,
                fontSize: fontSize,
                isVisible: true
            )
            .zIndex(15)
        }

        if hasTaskLines {
            CanvasNoteCardTaskTapOverlay(
                content: draftText,
                maxWidth: contentWidth,
                fontSize: fontSize,
                scrollOffset: contentScrollOffset,
                onToggleTaskRawLine: toggleTaskRawLine
            )
            .zIndex(10)
        }
    }

    private func handleAppear() {
        let prepared = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(
            in: initialText,
            vaultURL: vaultURL
        )
        draftText = prepared
        usesInlineImageEditor = vaultURL != nil
            && !NoteCardEmbedSupport.imageEmbedRanges(in: prepared, vaultURL: vaultURL).isEmpty
        if prepared != initialText {
            onTextEdited(prepared, false)
        }
        onRegisterImageInserter?(insertImageAttachment)
        #if os(macOS)
        DispatchQueue.main.async {
            isFocused = true
        }
        #else
        Task { @MainActor in
            isFocused = true
        }
        #endif
    }

    @discardableResult
    private func insertImageAttachment(_ data: Data, _ suggestedName: String?) -> Bool {
        guard let vaultURL else { return false }
        guard let path = try? VaultFilesystem.saveCanvasImage(
            data: data,
            vaultURL: vaultURL,
            suggestedName: suggestedName
        ) else { return false }

        CanvasImageCache.shared.cacheDisplayImageSync(
            data: data,
            cardID: "note-embed|\(path)",
            contentKey: path
        )
        if let cgImage = CanvasImageCache.shared.cachedImage(forCardID: "note-embed|\(path)", content: path) {
            let size = NoteCardInlineImageMetrics.displaySize(for: cgImage, maxWidth: contentWidth)
            NoteCardEmbedLayoutMetrics.store(height: size.height, path: path, maxWidth: contentWidth)
        }

        usesInlineImageEditor = true
        insertEmbedSnippet("![[\(path)]]")
        onImageEmbedSaved?(path)
        return true
    }

    private func insertEmbedSnippet(_ snippet: String) {
        let normalized = NoteCardEmbedEditingSupport.normalizedAttachmentSnippet(
            snippet,
            in: draftText,
            range: selectedRange
        )
        let result = MarkdownEditingSupport.insertText(normalized, in: draftText, range: selectedRange)
        let sanitized = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(
            in: result.text,
            vaultURL: vaultURL,
            selectedRange: result.selectedRange
        )
        draftText = sanitized.text
        selectedRange = sanitized.selectedRange ?? result.selectedRange
        if snippet.hasPrefix("![["),
           let caret = NoteCardEmbedEditingSupport.caretBelowLastImageEmbed(in: sanitized.text, vaultURL: vaultURL) {
            selectedRange = caret
        }
        onTextEdited(sanitized.text, false)
    }

    private func toggleTaskRawLine(_ rawLine: String) {
        guard let updated = NoteCardTaskSupport.toggleTask(matchingRawLine: rawLine, in: draftText) else { return }
        draftText = updated
        onTextEdited(updated, false)
    }
}
