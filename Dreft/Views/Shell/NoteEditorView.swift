import SwiftUI

enum NoteSplitLayout: String, Equatable {
    case none
    case right
    case down
}

struct NoteEditorView: View {
    @Bindable var workspace: WorkspaceStore
    let fileID: String
    @Binding var isReading: Bool
    @Binding var splitLayout: NoteSplitLayout
    @Binding var showFindBar: Bool

    @State private var draftTitle = ""
    @State private var draftContent = ""
    @State private var loadedFileID: String?
    @State private var findQuery = ""
    @State private var replaceQuery = ""
    @State private var bodySelectedRange = NSRange(location: 0, length: 0)
    @State private var wikilinkCaretRect: CGRect = .zero
    @State private var wikilinkSuggestIndex = 0
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isBodyFocused: Bool

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

    private var findMatchCount: Int {
        guard !findQuery.isEmpty else { return 0 }
        return draftContent.components(separatedBy: findQuery).count - 1
    }

    var body: some View {
        if file != nil {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if showFindBar {
                        findReplaceBar
                    }
                    editorSurface
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                noteStatusBar
            }
            .background(AppColors.canvasBackground)
            .onAppear { loadDraftIfNeeded() }
            .onChange(of: fileID) { _, _ in
                loadDraftIfNeeded()
            }
            .onChange(of: draftTitle) { _, _ in commitTitle() }
            .onChange(of: draftContent) { _, newValue in
                workspace.updateNoteContent(for: fileID, content: newValue)
            }
            .onDisappear { flushDraft() }
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
            if isReading {
                readingSurface
            } else {
                editingSurface
            }
        case .right:
            HStack(spacing: 0) {
                editingSurface
                Rectangle().fill(AppColors.borderSubtle).frame(width: 1)
                previewSurface
            }
        case .down:
            VStack(spacing: 0) {
                editingSurface
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

            if !findQuery.isEmpty {
                Text("\(findMatchCount) matches")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textMuted)
            }

            TextField("Replace", text: $replaceQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 160)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppColors.toolbarBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(isReading)

            Button("Replace") { replaceFirstMatch() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .disabled(isReading || findQuery.isEmpty)

            Button("Replace all") { replaceAllMatches() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .disabled(isReading || findQuery.isEmpty)

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
    }

    private var previewSurface: some View {
        NoteMarkdownPreview(content: draftContent) { openWikilink($0) }
    }

    private func replaceFirstMatch() {
        guard let range = draftContent.range(of: findQuery) else { return }
        draftContent.replaceSubrange(range, with: replaceQuery)
    }

    private func replaceAllMatches() {
        guard !findQuery.isEmpty else { return }
        draftContent = draftContent.replacingOccurrences(of: findQuery, with: replaceQuery)
    }

    private var editingSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("", text: $draftTitle, prompt: Text("Untitled"))
                    .font(.system(size: 40, weight: .bold))
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppColors.textPrimary)
                    .focused($isTitleFocused)
                    .onSubmit { commitTitle() }

                NoteBodyTextView(
                    text: $draftContent,
                    selectedRange: $bodySelectedRange,
                    caretRect: $wikilinkCaretRect,
                    isFocused: $isBodyFocused,
                    files: workspace.files,
                    suggestSelectedIndex: $wikilinkSuggestIndex
                )
            }
            .padding(.horizontal, 56)
            .padding(.top, 28)
            .padding(.bottom, 56)
            .frame(maxWidth: AppColors.noteReadableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
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

    private func loadDraftIfNeeded() {
        guard loadedFileID != fileID, let file else { return }
        draftTitle = file.name
        draftContent = file.noteContent
        loadedFileID = fileID
    }

    private func commitTitle() {
        guard file != nil else { return }
        workspace.renameFile(fileID, to: draftTitle)
    }

    private func flushDraft() {
        workspace.updateNoteContent(for: fileID, content: draftContent)
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
