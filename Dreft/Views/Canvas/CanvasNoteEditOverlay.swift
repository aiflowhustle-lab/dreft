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
                hideResolvedImageEmbeds: vaultURL != nil,
                onTextEdited: onTextEdited,
                toolbarBridge: toolbarBridge,
                onImageAttachmentDrop: insertImageAttachment,
                layoutRefreshToken: imageCacheRevision,
                onContentScroll: { metrics in
                    Task { @MainActor in
                        scrollMetrics = metrics
                        contentScrollOffset = metrics.offset
                    }
                }
            )

            if vaultURL != nil {
                CanvasNoteCardImageOverlay(
                    content: draftText,
                    vaultURL: vaultURL,
                    maxImageWidth: contentWidth,
                    fontSize: fontSize,
                    cacheRevision: imageCacheRevision,
                    scrollOffset: contentScrollOffset
                )
                .allowsHitTesting(false)
            }

            if isFocused, vaultURL != nil {
                CanvasNoteEditingChrome(
                    caretRect: caretRect,
                    selectionRects: selectionRects,
                    fontSize: fontSize
                )
                .zIndex(15)
            }

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
        .onAppear {
            let prepared = NoteCardEmbedEditingSupport.sanitizeEmbedSpacing(
                in: initialText,
                vaultURL: vaultURL
            )
            draftText = prepared
            if prepared != initialText {
                onTextEdited(prepared, false)
            }
            onRegisterImageInserter?(insertImageAttachment)
            Task { @MainActor in
                isFocused = true
            }
        }
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

    @discardableResult
    private func insertImageAttachment(_ data: Data, _ suggestedName: String?) -> Bool {
        guard let vaultURL else { return false }
        guard let path = try? VaultFilesystem.saveCanvasImage(
            data: data,
            vaultURL: vaultURL,
            suggestedName: suggestedName
        ) else { return false }

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
        onTextEdited(sanitized.text, false)
    }
}

private struct CanvasNoteEditingChrome: View {
    let caretRect: CGRect
    let selectionRects: [CGRect]
    let fontSize: CGFloat

    @State private var caretVisible = true

    private var caretHeight: CGFloat {
        max(4, min(caretRect.height > 1 ? caretRect.height : fontSize * 1.15, fontSize * 1.35))
    }

    private var showsCaret: Bool {
        caretRect.maxY > 0 || caretRect.maxX > 0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(selectionRects.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppColors.selectionStroke.opacity(0.24))
                    .frame(width: max(2, rect.width), height: max(4, rect.height))
                    .position(x: rect.midX, y: rect.midY)
            }

            if showsCaret, selectionRects.isEmpty {
                Rectangle()
                    .fill(AppColors.textPrimary)
                    .frame(width: 2, height: caretHeight)
                    .position(x: caretRect.minX + 1, y: caretRect.midY)
                    .opacity(caretVisible ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                caretVisible.toggle()
            }
        }
    }
}
