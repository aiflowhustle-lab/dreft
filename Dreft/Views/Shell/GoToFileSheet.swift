import SwiftUI

struct GoToFileSheet: View {
    @Bindable var workspace: WorkspaceStore
    @Binding var isPresented: Bool
    var replacingTabID: String?
    /// When set, chosen files open through this handler instead of the main tab group.
    var onFileSelected: ((WorkspaceFileEntry) -> Void)?

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private let maxPanelWidth: CGFloat = 560
    private let rowHeight: CGFloat = 38
    private let maxListHeight: CGFloat = 380

    private var filteredFiles: [WorkspaceFileEntry] {
        workspace.goToFileResults(matching: query)
    }

    private var listHeight: CGFloat {
        if filteredFiles.isEmpty { return 52 }
        return min(CGFloat(filteredFiles.count) * rowHeight, maxListHeight)
    }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = min(maxPanelWidth, max(280, geo.size.width * 0.92))
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                VStack(spacing: 0) {
                    TextField("Find or create a note...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isSearchFocused)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .onSubmit { openSelected() }
                        .onChange(of: query) { _, _ in
                            selectedIndex = 0
                        }

                    Divider().background(AppColors.border)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if filteredFiles.isEmpty {
                                    Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? "No files in vault"
                                         : "No matches — press ⇧↵ to create")
                                        .foregroundStyle(AppColors.textSecondary)
                                        .frame(maxWidth: .infinity, minHeight: listHeight, alignment: .center)
                                } else {
                                    ForEach(Array(filteredFiles.enumerated()), id: \.element.id) { index, file in
                                        Button {
                                            selectedIndex = index
                                            openSelected()
                                        } label: {
                                            GoToFileRow(
                                                file: file,
                                                isSelected: index == selectedIndex
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .id(index)
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: listHeight)
                        .onChange(of: selectedIndex) { _, newIndex in
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }

                    Divider().background(AppColors.border)

                    HStack(spacing: 14) {
                        hint("↑↓", "to navigate")
                        hint("↵", "to open")
                        hint("⇧↵", "to create")
                        hint("esc", "to dismiss")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }
                .frame(width: panelWidth)
                .background(AppColors.canvasBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border))
                .shadow(color: .black.opacity(0.45), radius: 28, y: 8)
            }
        }
        .onAppear {
            query = ""
            selectedIndex = 0
            isSearchFocused = true
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.shift) {
                createFromQuery()
            } else {
                openSelected()
            }
            return .handled
        }
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key).foregroundStyle(AppColors.textPrimary)
            Text(text)
        }
    }

    private func moveSelection(by delta: Int) {
        let count = filteredFiles.count
        guard count > 0 else { return }
        selectedIndex = min(count - 1, max(0, selectedIndex + delta))
    }

    private func openSelected() {
        guard selectedIndex < filteredFiles.count else {
            createFromQuery()
            return
        }
        let file = filteredFiles[selectedIndex]
        if let onFileSelected {
            onFileSelected(file)
        } else {
            workspace.openFileFromQuickSwitcher(
                file,
                replacingTabID: replacingTabID
            )
        }
        dismiss()
    }

    private func createFromQuery() {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if onFileSelected != nil {
            workspace.reportVaultError(
                title: "Create note",
                message: "Creating a new note from Go to file is only available in the main tab group."
            )
            return
        }
        workspace.createNote(named: name, replacingTabID: replacingTabID)
        dismiss()
    }

    private func dismiss() {
        isPresented = false
    }
}

private struct GoToFileRow: View {
    let file: WorkspaceFileEntry
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(AppColors.accentBlue)
                    .clipShape(Circle())
            } else {
                Color.clear.frame(width: 20, height: 20)
            }

            Text(file.name)
                .foregroundStyle(isSelected || isHovered ? AppColors.textPrimary : AppColors.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if file.parentFolderID != nil {
                Text(file.relativePath)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(1)
            }

            if let badge = file.badge ?? kindBadge(for: file.kind) {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(rowBackground)
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
    }

    private var rowBackground: Color {
        if isSelected { return Color.white.opacity(0.11) }
        if isHovered { return Color.white.opacity(0.07) }
        return Color.clear
    }

    private func kindBadge(for kind: WorkspaceFileKind) -> String? {
        switch kind {
        case .note: "MD"
        case .canvas: "CANVAS"
        case .folder: nil
        case .image: "IMAGE"
        }
    }
}
