import SwiftUI
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif
#if os(macOS)
import AppKit
#endif

enum NoteSplitLayout: String, Equatable {
    case none
    case right
    case down
}

struct NoteEditorView: View {
    @Bindable var workspace: WorkspaceStore
    var entitlements: EntitlementManager
    let fileID: String
    @Binding var isReading: Bool
    @Binding var splitLayout: NoteSplitLayout
    @Binding var showFindBar: Bool

    @State private var draftTitle = ""
    @State private var draftContent = ""
    @State private var loadedFileID: String?
    @State private var findQuery = ""
    @State private var replaceQuery = ""
    @State private var findCaseInsensitive = false
    @State private var findMatchRange = NSRange(location: NSNotFound, length: 0)
    @State private var selectionRevealToken = 0
    @State private var bodySelectedRange = NSRange(location: 0, length: 0)
    @State private var wikilinkCaretRect: CGRect = .zero
    @State private var bodySelectionRects: [CGRect] = []
    @State private var wikilinkSuggestIndex = 0
    @State private var titleCommitTask: Task<Void, Never>?
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isBodyFocused: Bool
    @FocusState private var isFindFieldFocused: Bool
    @StateObject private var noteToolbarBridge = NoteFormattingToolbarBridge()
    @State private var usesInlineImageEditor = false
    #if os(iOS)
    @State private var showNoteAttachmentMenu = false
    @State private var showNotePhotoPicker = false
    @State private var showNoteCamera = false
    @State private var showNoteFileImporter = false
    #endif
    #if canImport(PhotosUI)
    @State private var noteAttachmentPhotoItem: PhotosPickerItem?
    #endif

    private var file: WorkspaceFileEntry? {
        workspace.files.first { $0.id == fileID }
    }

    private var displayTitle: String {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private var wordCount: Int {
        draftContent
            .split { $0.isWhitespace || $0.isNewline }
            .filter { !$0.isEmpty }
            .count
    }

    private var characterCount: Int {
        draftContent.count
    }

    private var findOptions: NoteFindReplaceOptions {
        findCaseInsensitive ? .caseInsensitive : []
    }

    private var findMatchCount: Int {
        NoteFindReplaceSupport.matchCount(of: findQuery, in: draftContent, options: findOptions)
    }

    private var findStatusLabel: String {
        guard !findQuery.isEmpty else { return "" }
        if findMatchCount == 0 { return "No matches" }
        if findMatchRange.location != NSNotFound,
           let ordinal = NoteFindReplaceSupport.matchOrdinal(
            for: findMatchRange,
            query: findQuery,
            in: draftContent,
            options: findOptions
           ) {
            return "\(ordinal.index) of \(ordinal.total)"
        }
        return "\(findMatchCount) matches"
    }

    private var isWriteBlocked: Bool {
        !entitlements.canWrite
    }

    private var editorHideResolvedImageEmbeds: Bool {
        workspace.activeVaultURL != nil && usesInlineImageEditor
    }

    var body: some View {
        if file != nil {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if entitlements.isReadOnly {
                        ReadOnlyBanner {
                            entitlements.presentPaywall(.readOnlyBanner)
                        }
                    }
                    if showFindBar {
                        findReplaceBar
                    }
                    editorSurface
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsSwiftUIStatusBar {
                    noteStatusBar
                }
            }
            .background(AppColors.canvasBackground)
            .onAppear {
                loadDraftIfNeeded()
                enforceReadOnlyModeIfNeeded()
                #if os(iOS)
                syncAccessoryStatusToToolbarBridge()
                #endif
            }
            .onChange(of: fileID) { _, _ in
                loadDraftIfNeeded()
                enforceReadOnlyModeIfNeeded()
            }
            .onChange(of: entitlements.accessState) { _, _ in
                enforceReadOnlyModeIfNeeded()
            }
            .onChange(of: draftTitle) { _, _ in
                guard !isWriteBlocked else { return }
                scheduleTitleCommit()
            }
            .onChange(of: draftContent) { _, newValue in
                guard !isWriteBlocked else { return }
                workspace.updateNoteContent(for: fileID, content: newValue)
                #if os(iOS)
                syncAccessoryStatusToToolbarBridge()
                #endif
            }
            .onChange(of: workspace.saveStatus) { _, _ in
                #if os(iOS)
                syncAccessoryStatusToToolbarBridge()
                #endif
            }
            .onChange(of: showFindBar) { _, isVisible in
                if isVisible {
                    isReading = false
                    isFindFieldFocused = true
                    if !findQuery.isEmpty {
                        findNextMatch()
                    }
                } else {
                    findMatchRange = NSRange(location: NSNotFound, length: 0)
                }
            }
            .onChange(of: findQuery) { _, _ in
                guard showFindBar, !findQuery.isEmpty else {
                    findMatchRange = NSRange(location: NSNotFound, length: 0)
                    return
                }
                findNextMatch()
            }
            .onChange(of: findCaseInsensitive) { _, _ in
                guard showFindBar, !findQuery.isEmpty else { return }
                findNextMatch()
            }
            .onDisappear {
                titleCommitTask?.cancel()
                flushDraft()
                #if os(iOS)
                noteToolbarBridge.accessoryStatus = nil
                #endif
            }
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.canvasBackground)
        }
    }

    @ViewBuilder
    private var editorSurface: some View {
        switch splitLayout {
        case .none:
            if isReading || isWriteBlocked {
                readingSurface
            } else {
                editingSurface
            }
        case .right:
            HStack(spacing: 0) {
                if isReading || isWriteBlocked {
                    readingSurface
                } else {
                    editingSurface
                }
                Rectangle().fill(AppColors.borderSubtle).frame(width: 1)
                previewSurface
            }
        case .down:
            VStack(spacing: 0) {
                if isReading || isWriteBlocked {
                    readingSurface
                } else {
                    editingSurface
                }
                Rectangle().fill(AppColors.borderSubtle).frame(height: 1)
                previewSurface
            }
        }
    }

    private var findReplaceBar: some View {
        HStack(spacing: 10) {
            TextField("Find", text: $findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 160)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppColors.toolbarBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .focused($isFindFieldFocused)
                .onSubmit { findNextMatch() }
                #if os(macOS)
                .onExitCommand { showFindBar = false }
                #endif

            Button {
                findPreviousMatch()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.textSecondary)
            .disabled(isReading || findQuery.isEmpty)

            Button {
                findNextMatch()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.textSecondary)
            .disabled(isReading || findQuery.isEmpty)

            if !findQuery.isEmpty {
                Text(findStatusLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(findMatchCount == 0 ? AppColors.textMuted : AppColors.textSecondary)
                    .frame(minWidth: 72, alignment: .leading)
            }

            Toggle(isOn: $findCaseInsensitive) {
                Text("Aa")
                    .font(.system(size: 11, weight: .semibold))
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(findCaseInsensitive ? AppColors.textPrimary : AppColors.textMuted)
            .help("Match case")

            TextField("Replace", text: $replaceQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 160)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppColors.toolbarBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(isReading)
                .onSubmit { replaceCurrentMatch() }

            Button("Replace") { replaceCurrentMatch() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .disabled(isReading || findQuery.isEmpty)

            Button("Replace all") { replaceAllMatches() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .disabled(isReading || findQuery.isEmpty || findMatchCount == 0)

            Spacer()

            Button {
                showFindBar = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.textMuted)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 8)
        .background(AppColors.tabBarBackground)
        #if os(macOS)
        .background {
            Group {
                Button("") { findNextMatch() }
                    .keyboardShortcut("g", modifiers: .command)
                Button("") { findPreviousMatch() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            .hidden()
        }
        #endif
    }

    private var previewSurface: some View {
        NoteMarkdownPreview(content: draftContent) { openWikilink($0) }
    }

    private func revealFindMatch(_ range: NSRange) {
        findMatchRange = range
        bodySelectedRange = range
        selectionRevealToken &+= 1
        isBodyFocused = true
    }

    private func findNextMatch() {
        guard !findQuery.isEmpty else { return }
        let start = bodySelectedRange.location + bodySelectedRange.length
        guard let match = NoteFindReplaceSupport.findNext(
            in: draftContent,
            query: findQuery,
            after: start,
            wrap: true,
            options: findOptions
        ) else {
            findMatchRange = NSRange(location: NSNotFound, length: 0)
            return
        }
        revealFindMatch(match)
    }

    private func findPreviousMatch() {
        guard !findQuery.isEmpty else { return }
        let start = bodySelectedRange.location
        guard let match = NoteFindReplaceSupport.findPrevious(
            in: draftContent,
            query: findQuery,
            before: start,
            wrap: true,
            options: findOptions
        ) else {
            findMatchRange = NSRange(location: NSNotFound, length: 0)
            return
        }
        revealFindMatch(match)
    }

    private func replaceCurrentMatch() {
        guard !findQuery.isEmpty else { return }
        guard let result = NoteFindReplaceSupport.replaceCurrent(
            in: draftContent,
            query: findQuery,
            replacement: replaceQuery,
            selectedRange: bodySelectedRange,
            options: findOptions
        ) else { return }
        draftContent = result.text
        revealFindMatch(result.selectedRange)
    }

    private func replaceAllMatches() {
        guard !findQuery.isEmpty else { return }
        draftContent = NoteFindReplaceSupport.replaceAll(
            in: draftContent,
            query: findQuery,
            replacement: replaceQuery,
            options: findOptions
        )
        findMatchRange = NSRange(location: NSNotFound, length: 0)
        bodySelectedRange = NSRange(location: 0, length: 0)
    }

    @ViewBuilder
    private var editingSurface: some View {
        #if os(iOS)
        if usesStandalonePadEditor {
            iPadStandaloneEditingSurface
        } else {
            scrollEditingSurface
        }
        #else
        scrollEditingSurface
        #endif
    }

    #if os(iOS)
    private var usesStandalonePadEditor: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var showsSwiftUIStatusBar: Bool {
        !usesStandalonePadEditor
    }

    private var iPadStandaloneEditingSurface: some View {
        noteAttachmentModifiers {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 14) {
                    TextField("", text: $draftTitle, prompt: Text("Untitled"))
                        .font(.system(size: 34, weight: .bold))
                        .textFieldStyle(.plain)
                        .foregroundStyle(AppColors.textPrimary)
                        .focused($isTitleFocused)
                        .onSubmit {
                            focusNoteBody()
                        }

                    NoteBodyTextView(
                        text: $draftContent,
                        selectedRange: $bodySelectedRange,
                        caretRect: $wikilinkCaretRect,
                        selectionRects: $bodySelectionRects,
                        isFocused: $isBodyFocused,
                        files: workspace.files,
                        suggestSelectedIndex: $wikilinkSuggestIndex,
                        vaultURL: workspace.activeVaultURL,
                        hideResolvedImageEmbeds: editorHideResolvedImageEmbeds,
                        imageEmbedMaxWidth: AppColors.noteReadableWidth,
                        toolbarBridge: noteToolbarBridge,
                        onImageAttachmentDrop: insertImageAttachment,
                        selectionRevealToken: selectionRevealToken,
                        fillsAvailableHeight: true
                    )
                    .frame(width: geometry.size.width, height: max(240, geometry.size.height - 52))
                }
                .padding(.horizontal, 56)
                .padding(.top, 12)
                .frame(maxWidth: AppColors.noteReadableWidth, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func syncAccessoryStatusToToolbarBridge() {
        guard usesStandalonePadEditor else {
            noteToolbarBridge.accessoryStatus = nil
            return
        }

        let saveLabel: String? = switch workspace.saveStatus {
        case .idle: nil
        case .saving: "Saving…"
        case .saved: "Saved"
        }

        noteToolbarBridge.accessoryStatus = NoteEditorAccessoryStatus(
            saveLabel: saveLabel,
            backlinkCount: workspace.backlinkCount(for: fileID),
            wordCount: wordCount,
            characterCount: characterCount
        )
    }
    #else
    private var showsSwiftUIStatusBar: Bool { true }
    #endif

    private var scrollEditingSurface: some View {
        noteAttachmentModifiers {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("", text: $draftTitle, prompt: Text("Untitled"))
                        .font(.system(size: 40, weight: .bold))
                        .textFieldStyle(.plain)
                        .foregroundStyle(AppColors.textPrimary)
                        .focused($isTitleFocused)
                        .onSubmit {
                            focusNoteBody()
                        }

                    NoteBodyTextView(
                        text: $draftContent,
                        selectedRange: $bodySelectedRange,
                        caretRect: $wikilinkCaretRect,
                        selectionRects: $bodySelectionRects,
                        isFocused: $isBodyFocused,
                        files: workspace.files,
                        suggestSelectedIndex: $wikilinkSuggestIndex,
                        vaultURL: workspace.activeVaultURL,
                        hideResolvedImageEmbeds: editorHideResolvedImageEmbeds,
                        imageEmbedMaxWidth: AppColors.noteReadableWidth,
                        toolbarBridge: noteToolbarBridge,
                        onImageAttachmentDrop: insertImageAttachment,
                        selectionRevealToken: selectionRevealToken
                    )
                }
                .padding(.horizontal, 56)
                .padding(.top, 28)
                .padding(.bottom, 56)
                .frame(maxWidth: AppColors.noteReadableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        }
    }

    @ViewBuilder
    private func noteAttachmentModifiers<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if os(iOS)
        content()
            .photosPicker(isPresented: $showNotePhotoPicker, selection: $noteAttachmentPhotoItem, matching: .images)
            .onChange(of: noteAttachmentPhotoItem) { _, item in
                guard let item else { return }
                Task { await importNoteAttachmentPhoto(item) }
            }
            .fullScreenCover(isPresented: $showNoteCamera) {
                CameraImagePicker(
                    onImage: { data in
                        _ = insertImageAttachment(data, "photo.jpg")
                    },
                    onCancel: {
                        showNoteCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .overlay {
                NoteInsertAttachmentMenuOverlay(
                    isPresented: $showNoteAttachmentMenu,
                    onPhotoLibrary: { showNotePhotoPicker = true },
                    onTakePhoto: { showNoteCamera = true },
                    onChooseFile: { showNoteFileImporter = true }
                )
            }
            .fileImporter(
                isPresented: $showNoteFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                importNoteAttachmentFile(from: result)
            }
            .onAppear {
                noteToolbarBridge.onInsertAttachment = {
                    showNoteAttachmentMenu = true
                }
            }
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                handleNoteImageDrop(providers)
            }
        #elseif os(macOS)
        content()
            .onAppear {
                noteToolbarBridge.onInsertAttachment = {
                    openMacNoteAttachmentPanel()
                }
            }
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                handleNoteImageDrop(providers)
            }
        #else
        content()
        #endif
    }

    private var readingSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(displayTitle)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(" ")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textPrimary)
                } else {
                    Text(NoteMarkdownRenderer.linkedPreviewAttributedString(from: draftContent))
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineSpacing(4)
                        .tint(AppColors.noteLink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 56)
            .padding(.top, 28)
            .padding(.bottom, 56)
            .frame(maxWidth: AppColors.noteReadableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .environment(\.openURL, OpenURLAction { url in
            if let target = NoteMarkdownRenderer.wikilinkTarget(from: url) {
                openWikilink(target)
                return .handled
            }
            return .systemAction
        })
    }

    private var noteStatusBar: some View {
        HStack(spacing: 14) {
            saveStatusLabel

            Spacer()

            Text("\(workspace.backlinkCount(for: fileID)) backlinks")
            statusDivider
            Image(systemName: isReading ? "book" : "pencil")
            statusDivider
            Text("\(wordCount) words")
            statusDivider
            Text("\(characterCount) characters")
        }
        .font(.system(size: 11))
        .foregroundStyle(AppColors.textMuted)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(AppColors.canvasBackground)
    }

    private var statusDivider: some View {
        Text("•")
            .foregroundStyle(AppColors.textMuted.opacity(0.55))
    }

    @ViewBuilder
    private var saveStatusLabel: some View {
        switch workspace.saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            Text("Saving…")
                .foregroundStyle(AppColors.textMuted)
        case .saved:
            Text("Saved")
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func loadDraftIfNeeded() {
        guard loadedFileID != fileID, let file else { return }
        draftTitle = file.name
        draftContent = file.noteContent
        loadedFileID = fileID
        if let vaultURL = workspace.activeVaultURL {
            usesInlineImageEditor = !NoteCardEmbedSupport.imageEmbedRanges(
                in: file.noteContent,
                vaultURL: vaultURL
            ).isEmpty
        } else {
            usesInlineImageEditor = false
        }
    }

    @discardableResult
    private func insertImageAttachment(_ data: Data, _ suggestedName: String?) -> Bool {
        guard let vaultURL = workspace.activeVaultURL else { return false }
        guard let path = try? VaultFilesystem.saveCanvasImage(
            data: data,
            vaultURL: vaultURL,
            suggestedName: suggestedName
        ) else { return false }

        let maxWidth = AppColors.noteReadableWidth
        CanvasImageCache.shared.cacheDisplayImageSync(
            data: data,
            cardID: "note-embed|\(path)",
            contentKey: path
        )
        if let cgImage = CanvasImageCache.shared.cachedImage(forCardID: "note-embed|\(path)", content: path) {
            let size = NoteCardInlineImageMetrics.displaySize(for: cgImage, maxWidth: maxWidth)
            NoteCardEmbedLayoutMetrics.store(height: size.height, path: path, maxWidth: maxWidth)
        }

        usesInlineImageEditor = true
        noteToolbarBridge.insertSnippet("![[\(path)]]")
        return true
    }

    private func handleNoteImageDrop(_ providers: [NSItemProvider]) -> Bool {
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

    #if os(iOS)
    private func importNoteAttachmentPhoto(_ item: PhotosPickerItem) async {
        defer {
            Task { @MainActor in
                noteAttachmentPhotoItem = nil
            }
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await MainActor.run {
            _ = insertImageAttachment(data, item.itemIdentifier)
        }
    }

    private func importNoteAttachmentFile(from result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        _ = insertImageAttachment(data, url.lastPathComponent)
    }
    #endif

    #if os(macOS)
    private func openMacNoteAttachmentPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        _ = insertImageAttachment(data, url.lastPathComponent)
    }
    #endif

    private func enforceReadOnlyModeIfNeeded() {
        guard isWriteBlocked else { return }
        isReading = true
        isTitleFocused = false
        isBodyFocused = false
        showFindBar = false
    }

    private func scheduleTitleCommit() {
        titleCommitTask?.cancel()
        titleCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            commitTitle()
        }
    }

    private func focusNoteBody() {
        titleCommitTask?.cancel()
        commitTitle()
        isTitleFocused = false
        Task { @MainActor in
            isBodyFocused = true
        }
    }

    private func commitTitle() {
        guard let file else { return }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != file.name else { return }
        workspace.renameFile(fileID, to: draftTitle)
    }

    private func flushDraft() {
        guard !isWriteBlocked else { return }
        titleCommitTask?.cancel()
        commitTitle()
        workspace.updateNoteContent(for: resolvedNoteFileID(), content: draftContent)
    }

    private func resolvedNoteFileID() -> String {
        if workspace.files.contains(where: { $0.id == fileID }) {
            return fileID
        }
        if let tabFileID = workspace.tabs.first(where: { $0.id == workspace.activeTabID })?.fileID,
           workspace.files.contains(where: { $0.id == tabFileID }) {
            return tabFileID
        }
        return fileID
    }

    private func openWikilink(_ target: String) {
        guard let linkedID = WikilinkParser.resolveLinkTarget(target, in: workspace.files) else {
            workspace.reportVaultError(
            title: "File not found",
            message: "No file in this vault matches \"\(target)\"."
            )
            return
        }
        workspace.selectFile(linkedID)
    }
}

struct NoteMarkdownPreview: View {
    let content: String
    let onOpenWikilink: (String) -> Void

    var body: some View {
        ScrollView {
            Group {
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing to preview")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textMuted)
                } else {
                    Text(NoteMarkdownRenderer.linkedPreviewAttributedString(from: content))
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineSpacing(4)
                        .tint(AppColors.noteLink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 36)
            .frame(maxWidth: AppColors.noteReadableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.canvasBackground)
        .environment(\.openURL, OpenURLAction { url in
            if let target = NoteMarkdownRenderer.wikilinkTarget(from: url) {
                onOpenWikilink(target)
                return .handled
            }
            return .systemAction
        })
    }
}

struct ObsidianViewModeButton: View {
    @Binding var isReading: Bool
    var canEnterEditMode: Bool = true
    var onEditBlocked: (() -> Void)? = nil
    var onToggle: (() -> Void)? = nil
    @State private var hovered = false

    private var iconName: String {
        isReading ? "square.and.pencil" : "book"
    }

    private var tooltipLines: [String] {
        if isReading {
            [
                "Current view: reading",
                "Click to edit",
                "⌘+Click to open to the right",
            ]
        } else {
            [
                "Current view: editing",
                "Click to read",
                "⌘+Click to open to the right",
            ]
        }
    }

    var body: some View {
        Button {
            if isReading && !canEnterEditMode {
                onEditBlocked?()
                return
            }
            isReading.toggle()
            onToggle?()
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovered ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hovered ? AppColors.sidebarSelection.opacity(0.85) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .background(alignment: .top) {
            if hovered {
                ObsidianTooltipCard(lines: tooltipLines)
                    .offset(y: 30)
                    .zIndex(20)
            }
        }
    }
}

private struct ObsidianTooltipCard: View {
    let lines: [String]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .top) {
            ObsidianTooltipArrow()
                .fill(Color.black.opacity(0.96))
                .frame(width: 12, height: 6)
                .offset(y: -6)
        }
    }
}

private struct ObsidianTooltipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
