import SwiftUI

struct VaultSearchSheet: View {
    @Bindable var store: CanvasStore
    @Bindable var workspace: WorkspaceStore
    let canvasSize: CGSize
    @FocusState private var isFocused: Bool

    private var allVaultFiles: [VaultFile] {
        VaultFile.openableFiles(from: workspace.files)
    }

    private var filteredFiles: [VaultFile] {
        VaultFile.filtered(allVaultFiles, matching: store.vaultSearchQuery)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack {
                    TextField("Type to search...", text: $store.vaultSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($isFocused)
                        .onSubmit { openSelected() }
                        .onChange(of: store.vaultSearchQuery) { _, _ in
                            store.vaultSelectedIndex = 0
                        }

                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppColors.shellBackground)
                .overlay(alignment: .bottom) { Divider().background(AppColors.border) }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if filteredFiles.isEmpty {
                                Text(store.vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? "No vault files"
                                     : "No matches")
                                    .foregroundStyle(AppColors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else {
                                ForEach(Array(filteredFiles.enumerated()), id: \.element.id) { index, file in
                                    Button {
                                        store.vaultSelectedIndex = index
                                        open(file)
                                    } label: {
                                        VaultSearchFileRow(
                                            file: file,
                                            isSelected: index == store.vaultSelectedIndex,
                                            onHover: { hovering in
                                                if hovering {
                                                    store.vaultSelectedIndex = index
                                                }
                                            }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .id(index)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: store.vaultSelectedIndex) { _, newIndex in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

                HStack(spacing: 16) {
                    vaultHint("↑↓", "to navigate")
                    vaultHint("↵", "to open")
                    vaultHint("esc", "to dismiss")
                }
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(AppColors.shellBackground)
                .overlay(alignment: .top) { Divider().background(AppColors.border) }
            }
            .frame(width: min(520, canvasSize.width * 0.9))
            .background(AppColors.canvasBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border))
            .shadow(radius: 24)
        }
        .onAppear {
            store.vaultSelectedIndex = 0
            store.setVaultFiles(workspace.files)
            isFocused = true
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
        .onKeyPress(.return, phases: .down) { _ in
            openSelected()
            return .handled
        }
    }

    private func vaultHint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key).foregroundStyle(AppColors.textPrimary)
            Text(text)
        }
    }

    private func moveSelection(by delta: Int) {
        let count = filteredFiles.count
        guard count > 0 else { return }
        store.vaultSelectedIndex = min(count - 1, max(0, store.vaultSelectedIndex + delta))
    }

    private func openSelected() {
        let files = filteredFiles
        guard store.vaultSelectedIndex < files.count else { return }
        open(files[store.vaultSelectedIndex])
    }

    private func open(_ file: VaultFile) {
        if store.pendingEndpointEdgeID != nil {
            store.addVaultFile(file, canvasSize: canvasSize)
            dismiss()
            return
        }

        switch file.kind {
        case .note, .canvas:
            if let entry = workspace.files.first(where: { $0.id == file.id }) {
                workspace.navigateToFile(entry)
            }
            dismiss()
        case .image:
            store.addVaultFile(file, canvasSize: canvasSize)
            dismiss()
        case .folder:
            dismiss()
        }
    }

    private func dismiss() {
        store.pendingEndpointEdgeID = nil
        store.pendingEndpointMenuCenter = nil
        store.isVaultOpen = false
    }
}

private struct VaultSearchFileRow: View {
    let file: VaultFile
    let isSelected: Bool
    var onHover: (Bool) -> Void = { _ in }

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .foregroundStyle(isSelected || isHovered ? AppColors.textPrimary : AppColors.textSecondary)
                    .lineLimit(1)
                if file.relativePath.contains("/") {
                    Text(file.relativePath)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(file.badge)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 36, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        #endif
    }

    private var rowBackground: Color {
        if isSelected { return Color.white.opacity(0.11) }
        if isHovered { return Color.white.opacity(0.07) }
        return Color.clear
    }
}
