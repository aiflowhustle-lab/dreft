import SwiftUI
#if os(macOS)
import AppKit
#endif

enum SidebarPanel: String, CaseIterable {
    case files
    case search
    case tags
    case allProperties
    case bookmarks

    var displayName: String {
        switch self {
        case .files: "Files"
        case .search: "Search"
        case .tags: "Tags"
        case .allProperties: "All properties"
        case .bookmarks: "Bookmarks"
        }
    }

    var iconName: String {
        switch self {
        case .files: "folder"
        case .search: "magnifyingglass"
        case .tags: "tag"
        case .allProperties: "archivebox"
        case .bookmarks: "bookmark"
        }
    }
}

// MARK: - Row 1: panel switcher (aligns with tab bar)

private struct PanelSwitcherButton: View {
    let systemName: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isActive || isHovered ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive ? AppColors.sidebarSelection : (isHovered ? AppColors.sidebarSelection.opacity(0.6) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .overlay(alignment: .top) {
            if isHovered {
                ShellToolbarTooltip(text: label)
                    .offset(y: 32)
                    .zIndex(100)
            }
        }
        #if os(iOS)
        .help(label)
        #endif
    }
}

struct SidebarPanelSwitcherBar: View {
    @Binding var sidebarVisible: Bool
    @Binding var activePanel: SidebarPanel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                PanelSwitcherButton(systemName: "folder", label: "Files", isActive: activePanel == .files) {
                    activePanel = .files
                }
                PanelSwitcherButton(systemName: "magnifyingglass", label: "Search", isActive: activePanel == .search) {
                    activePanel = .search
                }
                PanelSwitcherButton(systemName: "bookmark", label: "Bookmarks", isActive: activePanel == .bookmarks) {
                    activePanel = .bookmarks
                }
            }

            Spacer(minLength: 0)
        }
        .overlay(alignment: .trailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarVisible = false
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Collapse sidebar")
            .padding(.trailing, 10)
        }
        .padding(.leading, 46)
    }
}

// MARK: - Row 2: file explorer actions

private struct FolderTreeChevronPairIcon: View {
    enum Style {
        case collapseAll
        case expandAll
    }

    let style: Style

    var body: some View {
        VStack(spacing: 1) {
            switch style {
            case .collapseAll:
                Image(systemName: "chevron.down")
                Image(systemName: "chevron.up")
            case .expandAll:
                Image(systemName: "chevron.up")
                Image(systemName: "chevron.down")
            }
        }
        .font(.system(size: 12, weight: .bold))
    }
}

private struct ShellToolbarSymbolButton: View {
    let systemName: String
    let label: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isActive || isHovered ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive || isHovered ? AppColors.sidebarSelection : Color.clear)
                )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .overlay(alignment: .top) {
            if isHovered {
                ShellToolbarTooltip(text: label)
                    .offset(y: 32)
                    .zIndex(100)
            }
        }
        #if os(iOS)
        .help(label)
        #endif
    }
}

private struct ShellToolbarCustomIconButton<Icon: View>: View {
    let label: String
    var isActive: Bool = false
    let action: () -> Void
    @ViewBuilder private let icon: () -> Icon

    @State private var isHovered = false

    init(
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.label = label
        self.isActive = isActive
        self.action = action
        self.icon = icon
    }

    var body: some View {
        Button(action: action) {
            icon()
                .foregroundStyle(isActive || isHovered ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive || isHovered ? AppColors.sidebarSelection : Color.clear)
                )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .overlay(alignment: .top) {
            if isHovered {
                ShellToolbarTooltip(text: label)
                    .offset(y: 32)
                    .zIndex(100)
            }
        }
        #if os(iOS)
        .help(label)
        #endif
    }
}

private struct ShellToolbarTooltip: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            ShellTooltipArrow()
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.11, green: 0.11, blue: 0.11))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .fixedSize()
        .allowsHitTesting(false)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }
}

private struct ShellTooltipArrow: View {
    var body: some View {
        ShellTooltipArrowShape()
            .fill(Color(red: 0.11, green: 0.11, blue: 0.11))
            .frame(width: 12, height: 6)
            .overlay {
                ShellTooltipArrowShape()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct ShellTooltipArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct SidebarFileToolbar: View {
    @Bindable var workspace: WorkspaceStore
    var onNewNote: () -> Void
    var onNewFolder: () -> Void

    @State private var sortHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ShellToolbarSymbolButton(systemName: "square.and.pencil", label: "New note", action: onNewNote)
                ShellToolbarSymbolButton(systemName: "folder.badge.plus", label: "New folder", action: onNewFolder)
                sortOrderMenu
                expandCollapseAllButton
            }
            .fixedSize()

            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 38)
        .frame(height: 34)
        .zIndex(1)
    }

    private var sortOrderMenu: some View {
        Menu {
            sortOption(.nameAscending)
            sortOption(.nameDescending)
            Divider()
            sortOption(.modifiedNewToOld)
            sortOption(.modifiedOldToNew)
            Divider()
            sortOption(.createdNewToOld)
            sortOption(.createdOldToNew)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(sortHovered ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(sortHovered ? AppColors.sidebarSelection : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        #if os(macOS)
        .onHover { sortHovered = $0 }
        #endif
        .overlay(alignment: .top) {
            if sortHovered {
                ShellToolbarTooltip(text: "Change sort order")
                    .offset(y: 32)
                    .zIndex(100)
            }
        }
        #if os(iOS)
        .help("Change sort order")
        #endif
    }

    private var expandCollapseAllButton: some View {
        let isFullyExpanded = workspace.areAllFoldersExpanded
        let label = isFullyExpanded ? "Collapse all" : "Expand all"
        let style: FolderTreeChevronPairIcon.Style = isFullyExpanded ? .collapseAll : .expandAll

        return ShellToolbarCustomIconButton(label: label) {
            workspace.toggleExpandCollapseAllFolders()
        } icon: {
            FolderTreeChevronPairIcon(style: style)
        }
    }

    private func sortOption(_ order: SidebarSortOrder) -> some View {
        Button {
            workspace.sortOrder = order
        } label: {
            if workspace.sortOrder == order {
                Label(order.label, systemImage: "checkmark")
            } else {
                Text(order.label)
            }
        }
    }
}

// MARK: - Sidebar body (file list + footer)

private enum SidebarDropTarget: Equatable {
    case none
    case root
    case folder(String)
}

private struct SidebarTreeGuide: View {
    let isLast: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: 7, y: 0))
                path.addLine(to: CGPoint(x: 7, y: isLast ? 14 : 32))
                if isLast {
                    path.move(to: CGPoint(x: 7, y: 14))
                    path.addLine(to: CGPoint(x: 14, y: 14))
                }
            }
            .stroke(AppColors.borderSubtle, lineWidth: 1)
        }
        .frame(width: 16, height: 28)
    }
}

private struct SidebarFileRowView: View {
    @Bindable var workspace: WorkspaceStore
    let row: SidebarFileRow
    @Binding var dropTarget: SidebarDropTarget

    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    private var file: WorkspaceFileEntry { row.file }
    private var isActive: Bool { workspace.selectedFileID == file.id }
    private var isRenaming: Bool { workspace.inlineRenameFileID == file.id }
    private var isDropTarget: Bool {
        if case .folder(let id) = dropTarget { return id == file.id }
        return false
    }

    var body: some View {
        HStack(spacing: 0) {
            if row.depth > 0 {
                SidebarTreeGuide(isLast: row.isLastInParent)
            }

            HStack(spacing: 6) {
                if file.kind == .folder {
                    Image(systemName: workspace.isFolderExpanded(file.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.textMuted)
                        .frame(width: 12, height: 12)
                } else {
                    Color.clear.frame(width: 12, height: 12)
                }

                Group {
                    if isRenaming {
                        renameField
                    } else {
                        Text(file.name)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isRenaming, let badge = file.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColors.textMuted)
                        .textCase(.uppercase)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.leading, row.depth > 0 ? 2 : 10)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.leading, row.depth == 0 ? 6 : 10)
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .onTapGesture {
            guard !isRenaming else { return }
            if file.kind == .folder {
                workspace.toggleFolderExpanded(file.id)
                workspace.selectedFileID = file.id
            } else {
                workspace.selectFile(file.id)
            }
        }
        .contextMenu {
            if file.kind == .folder {
                folderContextMenu
            } else {
                fileContextMenu
            }
        }
        .if(file.isMovable) { view in
            view.draggable(file.id)
        }
        .if(file.kind == .folder) { view in
            view.dropDestination(for: String.self) { items, _ in
                guard let draggedID = items.first else { return false }
                workspace.moveFile(draggedID, toFolder: file.id)
                dropTarget = .none
                return true
            } isTargeted: { targeted in
                if targeted {
                    dropTarget = .folder(file.id)
                } else if case .folder(file.id) = dropTarget {
                    dropTarget = .none
                }
            }
        }
    }

    @ViewBuilder
    private var folderContextMenu: some View {
        Button("New note") { workspace.createNote(inFolder: file.id) }
        Button("New folder") { workspace.createFolder(inFolder: file.id) }
        Button("New canvas") { workspace.createCanvas(inFolder: file.id) }

        Divider()

        Button("Duplicate") { workspace.duplicateFile(file.id) }
        moveDestinationMenu(title: "Move folder to...")
        if workspace.isBookmarked(file.id) {
            Button("Remove bookmark") { workspace.removeBookmark(file.id) }
        }

        Divider()

        copyPathMenu

        Divider()

        #if os(macOS)
        Button("Reveal in Finder") { revealInFinder() }
        Divider()
        #endif

        Button("Rename...") { workspace.beginInlineRename(for: file.id) }
        Button("Delete") { workspace.deleteFile(file.id) }
    }

    @ViewBuilder
    private var fileContextMenu: some View {
        Button("Open in new tab") { workspace.openTab(for: file) }

        Divider()

        Button("Duplicate") { workspace.duplicateFile(file.id) }
        moveDestinationMenu(title: "Move file to...")
        Button {
            workspace.presentBookmarkEditor(for: file.id)
        } label: {
            if workspace.isBookmarked(file.id) {
                Label("Bookmark...", systemImage: "checkmark")
            } else {
                Text("Bookmark...")
            }
        }

        Divider()

        copyPathMenu

        Divider()

        #if os(macOS)
        Button("Open in default app") { openInDefaultApp() }
        Button("Reveal in Finder") { revealInFinder() }
        Divider()
        #endif

        Button("Rename...") { workspace.beginInlineRename(for: file.id) }
        Button("Delete") { workspace.deleteFile(file.id) }
    }

    private var renameField: some View {
        TextField("", text: $renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(AppColors.textPrimary)
            .focused($renameFocused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.selectionStroke.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AppColors.selectionStroke, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onSubmit { commitInlineRename() }
            .sidebarRenameEscKey { cancelInlineRename() }
            .onAppear {
                renameDraft = file.name
                DispatchQueue.main.async {
                    renameFocused = true
                }
            }
            .onChange(of: workspace.inlineRenameFileID) { _, newValue in
                if newValue != file.id {
                    renameFocused = false
                }
            }
    }

    private func commitInlineRename() {
        workspace.renameFile(file.id, to: renameDraft)
        workspace.endInlineRename()
    }

    private func cancelInlineRename() {
        workspace.endInlineRename()
    }

    private func moveDestinationMenu(title: String) -> some View {
        Menu(title) {
            if file.parentFolderID != nil {
                Button("Vault root") { workspace.moveFile(file.id, toFolder: nil) }
            }
            ForEach(workspace.availableMoveDestinations(for: file.id)) { folder in
                if folder.id != file.parentFolderID {
                    Button(folder.name) { workspace.moveFile(file.id, toFolder: folder.id) }
                }
            }
        }
    }

    private var copyPathMenu: some View {
        Menu("Copy path") {
            if let path = workspace.vaultRelativePath(for: file.id) {
                Button("from vault folder") { copyToPasteboard(path) }
            }
            if let path = workspace.diskPath(for: file.id) {
                Button("from system root") { copyToPasteboard(path) }
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    private func revealInFinder() {
        #if os(macOS)
        if let path = workspace.diskPath(for: file.id) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        #endif
    }

    #if os(macOS)
    private func openInDefaultApp() {
        if let path = workspace.diskPath(for: file.id) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
    #endif

    @ViewBuilder
    private var rowBackground: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.selectionStroke.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppColors.selectionStroke.opacity(0.55), lineWidth: 1)
                )
        } else if isActive {
            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.sidebarSelection)
        } else {
            Color.clear
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct SidebarView: View {
    @Bindable var workspace: WorkspaceStore
    @Binding var sidebarVisible: Bool
    @Binding var sidebarPanel: SidebarPanel
    var activePanel: SidebarPanel = .files
    /// Floating overlay style (iPad): transparent background, no built-in footer.
    var floatingStyle = false
    @State private var dropTarget: SidebarDropTarget = .none
    @State private var searchQuery = ""
    @State private var searchMatchCase = false
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            switch activePanel {
            case .files:
                filesPanel
            case .search:
                searchPanel
            case .tags:
                emptyStatePanel("No tags found")
            case .allProperties:
                emptyStatePanel("No properties found")
            case .bookmarks:
                bookmarksPanel
            }

            if !floatingStyle {
                sidebarFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if !floatingStyle {
                AppColors.shellBackground
            }
        }
    }

    private func emptyStatePanel(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var sidebarFooter: some View {
            HStack(spacing: 8) {
                Menu {
                    ForEach(workspace.vaults) { vault in
                        Button {
                            workspace.switchVault(vault.id)
                        } label: {
                            if vault.id == workspace.activeVault?.id {
                                Label(vault.name, systemImage: "checkmark")
                            } else {
                                Text(vault.name)
                            }
                        }
                    }
                    Divider()
                    Button("Manage vaults...") {
                        withAnimation(.easeOut(duration: 0.15)) {
                            workspace.isVaultManagerOpen = true
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(workspace.vaultName)
                            .foregroundStyle(AppColors.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
                SidebarFooterIconButton(systemName: "questionmark.circle", label: "Help") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        workspace.isHelpOpen = true
                    }
                }
                SidebarFooterIconButton(systemName: "gearshape", label: "Settings") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        workspace.isVaultManagerOpen = true
                    }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .overlay(alignment: .top) { ShellHairline() }
    }

    // MARK: Files panel

    private var filesPanel: some View {
        Group {
            SidebarFileToolbar(
                workspace: workspace,
                onNewNote: { workspace.createNote() },
                onNewFolder: { workspace.createFolder() }
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(workspace.visibleSidebarRows()) { row in
                        SidebarFileRowView(
                            workspace: workspace,
                            row: row,
                            dropTarget: $dropTarget
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background {
                    if dropTarget == .root {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColors.selectionStroke.opacity(0.45), lineWidth: 1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    }
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let draggedID = items.first else { return false }
                    workspace.moveFile(draggedID, toFolder: nil)
                    dropTarget = .none
                    return true
                } isTargeted: { targeted in
                    if targeted {
                        if case .folder = dropTarget { return }
                        dropTarget = .root
                    } else if dropTarget == .root {
                        dropTarget = .none
                    }
                }
            }
        }
    }

    // MARK: Search panel

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textMuted)

                    TextField("Search...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textPrimary)
                        .focused($searchFieldFocused)

                    Button {
                        searchMatchCase.toggle()
                    } label: {
                        Text("Aa")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(searchMatchCase ? AppColors.textPrimary : AppColors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Match case")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.inputFieldBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    searchFieldFocused
                                        ? AppColors.selectionStroke.opacity(0.7)
                                        : AppColors.floatingChromeBorder,
                                    lineWidth: 1
                                )
                        )
                )

                Button {} label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Search settings")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if searchQuery.isEmpty {
                if searchFieldFocused {
                    searchOptionsCard
                        .padding(.horizontal, 10)
                        .padding(.top, 2)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(searchResults) { file in
                            Button {
                                workspace.selectFile(file.id)
                            } label: {
                                HStack {
                                    Text(file.name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AppColors.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    if let badge = file.badge {
                                        Text(badge)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(AppColors.textMuted)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if searchResults.isEmpty {
                            Text("No results found.")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textMuted)
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            searchFieldFocused = false
        }
    }

    private var searchResults: [WorkspaceFileEntry] {
        let raw = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return [] }

        var term = raw
        var pathMode = false
        if raw.lowercased().hasPrefix("file:") {
            term = String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if raw.lowercased().hasPrefix("path:") {
            term = String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            pathMode = true
        }
        guard !term.isEmpty else { return [] }

        return workspace.files.filter { file in
            guard file.kind != .folder else { return false }
            let target = pathMode ? workspace.path(for: file.id) : file.name
            if searchMatchCase {
                return target.contains(term)
            }
            return target.localizedCaseInsensitiveContains(term)
        }
    }

    private var searchOptionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Search options")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            searchOptionRow(prefix: "path:", detail: "match path of the file")
            searchOptionRow(prefix: "file:", detail: "match file name")
            searchOptionRow(prefix: "tag:", detail: "search for tags")
            searchOptionRow(prefix: "line:", detail: "search keywords on same line")
            searchOptionRow(prefix: "section:", detail: "search keywords under same heading")
            searchOptionRow(prefix: "[property]", detail: "match property")

            Spacer().frame(height: 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.floatingChrome)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }

    private func searchOptionRow(prefix: String, detail: String) -> some View {
        Button {
            searchQuery = prefix == "[property]" ? "" : prefix
            searchFieldFocused = true
        } label: {
            (
                Text(prefix)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                + Text(" \(detail)")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Bookmarks panel

    private var bookmarksPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    ShellToolbarSymbolButton(systemName: "bookmark", label: "Bookmark active file") {
                        if let id = workspace.selectedFileID {
                            workspace.presentBookmarkEditor(for: id)
                        }
                    }
                    ShellToolbarCustomIconButton(label: "Collapse all") {
                        workspace.collapseAllFolders()
                    } icon: {
                        FolderTreeChevronPairIcon(style: .collapseAll)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)

            if workspace.bookmarkEntries.isEmpty {
                Spacer()
                Text("No bookmarks found")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textMuted)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(workspace.bookmarkEntries) { entry in
                            Button {
                                workspace.selectFile(entry.file.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppColors.selectionStroke)
                                    Text(entry.bookmark.title)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                bookmarkContextMenu(for: entry)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func bookmarkContextMenu(for entry: WorkspaceBookmarkEntry) -> some View {
        let file = entry.file

        Button("Open in new tab") {
            workspace.openTab(for: file)
        }
        Button("Open to the right") {
            workspace.openTabToRight(for: file)
        }
        Button("Open in new window") {
            workspace.reportNewWindowUnsupported()
        }

        Divider()

        Button("Rename...") {
            sidebarPanel = .files
            sidebarVisible = true
            workspace.beginInlineRename(for: file.id)
        }
        Button("Edit...") {
            workspace.presentBookmarkEditor(for: file.id)
        }

        Divider()

        Button("Reveal file in navigation") {
            sidebarPanel = .files
            sidebarVisible = true
            workspace.revealInNavigation(file.id)
        }

        Divider()

        Button("Remove") {
            workspace.removeBookmark(file.id)
        }
    }
}

private struct SidebarFooterIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? AppColors.sidebarSelection : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .help(label)
    }
}

#if os(macOS)
private struct SidebarRenameEscKeyModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onExitCommand(perform: action)
    }
}
#endif

private extension View {
    @ViewBuilder
    func sidebarRenameEscKey(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        modifier(SidebarRenameEscKeyModifier(action: action))
        #else
        self
        #endif
    }
}
