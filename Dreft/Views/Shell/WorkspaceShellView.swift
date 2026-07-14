import SwiftUI
#if os(iOS)
import UIKit
#endif

enum SidebarLayout {
    static let defaultWidth: CGFloat = 232
    static let minWidth: CGFloat = 180
    static let maxWidth: CGFloat = 480

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(maxWidth, max(minWidth, width))
    }
}

/// A second editor pane (tab group) created by Split right / Split down.
struct SplitPaneState {
    var orientation: NoteSplitLayout
    var tabs: [WorkspaceTab]
    var activeTabID: String

    var activeTab: WorkspaceTab? {
        tabs.first { $0.id == activeTabID } ?? tabs.first
    }

    static func newTabID() -> String {
        "t" + UUID().uuidString.prefix(8).lowercased()
    }
}

struct WorkspaceShellView: View {
    @State private var workspace: WorkspaceStore
    @State private var canvasDocuments: CanvasDocumentRegistry
    @State private var persistenceCoordinator: WorkspacePersistenceCoordinator?
    @State private var sidebarVisible = true
    @State private var rightSidebarVisible = false
    @State private var iconRailVisible = true
    @State private var sidebarPanel: SidebarPanel = .files
    @State private var showGoToFile = false
    @State private var noteIsReading = false
    @State private var noteSplitLayout: NoteSplitLayout = .none
    @State private var showNoteFindBar = false
    /// Obsidian-style second tab group: the split side is a full pane with its
    /// own tab bar, nav bar, and content — not a sub-view inside one tab.
    @State private var splitPane: SplitPaneState?
    @State private var splitPaneIsReading = false
    @State private var splitPaneShowFindBar = false
    /// When true, the Go-to-file picker opens files into the split pane.
    @State private var goToFileTargetsSplitPane = false
    @AppStorage("sidebarWidth") private var sidebarWidthStorage = SidebarLayout.defaultWidth
    @State private var sidebarWidth = SidebarLayout.defaultWidth
    @State private var isResizingSidebar = false
    #if os(iOS)
    /// Leading clearance for Stage Manager traffic lights when the app is windowed.
    @State private var stageManagerLeadingInset: CGFloat = 0
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let workspace = WorkspaceStore()
        let registry = CanvasDocumentRegistry()

        // Wire the canvas registry before the vault loads so document snapshots
        // reach it during `restore` (which scans the vault before restoring tabs).
        workspace.onVaultCanvasLoaded = { snapshots in
            registry.setVaultURL(workspace.activeVaultURL)
            registry.load(from: snapshots)
            if let vaultURL = workspace.activeVaultURL {
                registry.migrateEmbeddedImages(vaultURL: vaultURL)
            }
        }

        let loadResult = WorkspacePersistence.load()
        if let saved = loadResult.state {
            workspace.restore(from: saved)
            if loadResult.restoredFromBackup {
                workspace.reportVaultError(
                    title: "Couldn't read settings",
                    message: "Restored your workspace from the last backup."
                )
            }
        } else {
            workspace.bootstrapDefaultVaultIfNeeded()
        }

        _workspace = State(initialValue: workspace)
        _canvasDocuments = State(initialValue: registry)
    }

    private var activeTab: WorkspaceTab? {
        workspace.activeTab
    }

    private var documentTitle: String {
        workspace.documentTitle(for: activeTab)
    }

    private func startPersistenceIfNeeded() {
        guard persistenceCoordinator == nil else { return }
        workspace.onCanvasDocumentRemoved = { [canvasDocuments] fileID in
            canvasDocuments.remove(documentID: fileID)
        }
        workspace.onCanvasDocumentRekeyed = { [canvasDocuments] oldID, newID in
            canvasDocuments.rekey(documentID: oldID, to: newID)
        }
        let coordinator = WorkspacePersistenceCoordinator(
            workspace: workspace,
            documents: canvasDocuments
        )
        canvasDocuments.setVaultURL(workspace.activeVaultURL)
        coordinator.start()
        persistenceCoordinator = coordinator
    }

    private func bootstrapShellIfNeeded() {
        startPersistenceIfNeeded()
        sidebarWidth = SidebarLayout.clamped(CGFloat(sidebarWidthStorage))
    }

    var body: some View {
        Group {
        #if os(macOS)
        macShell
            .vaultErrorAlert(workspace: workspace)
        #else
        iosShell
            .vaultErrorAlert(workspace: workspace)
        #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                persistenceCoordinator?.refreshVaultFromDiskIfNeeded()
            }
            #if os(iOS)
            if phase == .background {
                persistenceCoordinator?.flushPendingChanges()
            }
            #endif
        }
    }

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("ipadSidebarPinned") private var ipadSidebarPinned = false
    #endif

    private var usesDesktopChrome: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    /// On iPad the sidebar floats over the canvas instead of being a fixed split pane.
    private var usesFloatingSidebar: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        false
        #endif
    }

    private var iconRailTopInset: CGFloat {
        #if os(macOS)
        AppColors.macTrafficLightInset
        #else
        8
        #endif
    }

    private var shellLayout: some View {
        HStack(spacing: 0) {
            #if os(macOS)
            if iconRailVisible && usesDesktopChrome {
                IconRailView(
                    workspace: workspace,
                    sidebarVisible: $sidebarVisible,
                    onGoToFile: { showGoToFile = true },
                    contentTopInset: iconRailTopInset
                )
                .frame(maxHeight: .infinity)
                ShellVerticalHairline()
                    .padding(.top, AppColors.chromeRowHeight)
            }
            #endif

            if sidebarVisible && usesDesktopChrome && !usesFloatingSidebar {
                sidebarColumn
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            editorColumn

            if rightSidebarVisible && usesDesktopChrome {
                ShellVerticalHairline()
                rightSidebarColumn
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(isResizingSidebar ? nil : .easeInOut(duration: 0.2), value: sidebarVisible)
        .animation(.easeInOut(duration: 0.2), value: rightSidebarVisible)
        .background(alignment: .top) {
            if usesDesktopChrome {
                AppColors.tabBarBackground
                    .frame(height: AppColors.chromeRowHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .top) {
            if usesDesktopChrome {
                chromeRowHairline
            }
        }
        #if os(iOS)
        .overlay(alignment: .topLeading) {
            floatingSidebarOverlay
        }
        #endif
    }

    #if os(iOS)
    private func dismissFloatingSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            sidebarVisible = false
        }
    }

    @ViewBuilder
    private var floatingSidebarOverlay: some View {
        if usesFloatingSidebar && sidebarVisible {
            ZStack(alignment: .topLeading) {
                if !ipadSidebarPinned {
                    // Invisible scrim: tapping anywhere outside dismisses the unpinned sidebar.
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { dismissFloatingSidebar() }
                }

                HStack(alignment: .top, spacing: 6) {
                    IPadIconRail(
                        workspace: workspace,
                        sidebarVisible: $sidebarVisible,
                        sidebarPanel: $sidebarPanel,
                        onGoToFile: { showGoToFile = true }
                    )
                    IPadFloatingSidebar(
                        workspace: workspace,
                        sidebarVisible: $sidebarVisible,
                        sidebarPanel: $sidebarPanel,
                        isPinned: $ipadSidebarPinned
                    )
                }
                .padding(.leading, 6)
                .padding(.vertical, 10)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            // Swipe left over the panel dismisses it.
                            if value.translation.width < -60,
                               abs(value.translation.width) > abs(value.translation.height) {
                                dismissFloatingSidebar()
                            }
                        }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }
    #endif

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            SidebarPanelSwitcherBar(sidebarVisible: $sidebarVisible, activePanel: $sidebarPanel)
                .frame(height: AppColors.chromeRowHeight)
                .background(AppColors.tabBarBackground)
                #if os(macOS)
                .background { MacWindowDragHandle() }
                #endif

            SidebarView(
                workspace: workspace,
                sidebarVisible: $sidebarVisible,
                sidebarPanel: $sidebarPanel,
                activePanel: sidebarPanel
            )
        }
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(AppColors.shellBackground)
        .overlay(alignment: .trailing) {
            ShellSidebarResizeHandle(
                width: $sidebarWidth,
                onResizeBegan: { isResizingSidebar = true },
                onCommit: {
                    isResizingSidebar = false
                    sidebarWidthStorage = sidebarWidth
                }
            )
        }
    }

    private var rightSidebarColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                Text("Backlinks")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                chromeIconButton("xmark", tip: "Collapse right sidebar") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        rightSidebarVisible = false
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: AppColors.chromeRowHeight)
            .background(AppColors.tabBarBackground)

            if let fileID = activeTab?.fileID {
                let linkedIDs = workspace.incomingLinkIDs(for: fileID)
                if linkedIDs.isEmpty {
                    Spacer()
                    Text("No backlinks found")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textMuted)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(linkedIDs, id: \.self) { linkedID in
                                if let file = workspace.files.first(where: { $0.id == linkedID }) {
                                    Button {
                                        workspace.selectFile(file.id)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: file.kind == .canvas ? "square.grid.2x2" : "doc.text")
                                                .font(.system(size: 11))
                                                .foregroundStyle(AppColors.textSecondary)
                                            Text(file.name)
                                                .font(.system(size: 12.5))
                                                .foregroundStyle(AppColors.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            } else {
                Spacer()
                Text("No active file")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textMuted)
                Spacer()
            }
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(AppColors.shellBackground)
    }

    @ViewBuilder
    private var editorColumn: some View {
        Group {
            if let pane = splitPane {
                if pane.orientation == .right {
                    HStack(spacing: 0) {
                        mainEditorPane
                        ShellVerticalHairline()
                        splitEditorPane
                    }
                } else {
                    VStack(spacing: 0) {
                        mainEditorPane
                        ShellHairline()
                        splitEditorPane
                    }
                }
            } else {
                mainEditorPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.canvasBackground)
    }

    private var mainEditorPane: some View {
        VStack(spacing: 0) {
            tabBar
                .frame(height: AppColors.chromeRowHeight)
                .background(AppColors.tabBarBackground)
                #if os(macOS)
                .background { MacWindowDragHandle() }
                #endif

            documentNavBar
            canvasArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Split pane (second tab group)

    /// Drives the Split right / Split down menu items for both panes.
    private var splitLayoutBinding: Binding<NoteSplitLayout> {
        Binding(
            get: { splitPane?.orientation ?? .none },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.18)) {
                    if newValue == .none {
                        splitPane = nil
                    } else {
                        openSplitPane(orientation: newValue)
                    }
                }
            }
        )
    }

    private func openSplitPane(orientation: NoteSplitLayout) {
        if var pane = splitPane {
            pane.orientation = orientation
            splitPane = pane
            return
        }
        guard var copy = activeTab else { return }
        copy.id = SplitPaneState.newTabID()
        splitPane = SplitPaneState(
            orientation: orientation,
            tabs: [copy],
            activeTabID: copy.id
        )
    }

    private func closeSplitPaneTab(_ tabID: String) {
        guard var pane = splitPane else { return }
        pane.tabs.removeAll { $0.id == tabID }
        if pane.tabs.isEmpty {
            withAnimation(.easeInOut(duration: 0.18)) { splitPane = nil }
            return
        }
        if pane.activeTabID == tabID {
            pane.activeTabID = pane.tabs[0].id
        }
        splitPane = pane
    }

    private func addSplitPaneTab() {
        guard var pane = splitPane else { return }
        let tab = WorkspaceTab(
            id: SplitPaneState.newTabID(),
            title: "New tab",
            kind: .newTab,
            fileID: nil
        )
        pane.tabs.append(tab)
        pane.activeTabID = tab.id
        splitPane = pane
    }

    private func openInSplitPane(_ file: WorkspaceFileEntry) {
        guard var pane = splitPane, file.kind == .note || file.kind == .canvas else { return }
        let tab = WorkspaceTab(
            id: SplitPaneState.newTabID(),
            title: file.name,
            kind: file.kind == .canvas ? .canvas : .note,
            fileID: file.id
        )
        if let index = pane.tabs.firstIndex(where: { $0.id == pane.activeTabID }),
           pane.tabs[index].kind == .newTab {
            pane.tabs[index] = tab
        } else {
            pane.tabs.append(tab)
        }
        pane.activeTabID = tab.id
        splitPane = pane
        splitPaneIsReading = false
        splitPaneShowFindBar = false
    }

    private var splitEditorPane: some View {
        VStack(spacing: 0) {
            splitPaneTabBar
                .frame(height: AppColors.chromeRowHeight)
                .background(AppColors.tabBarBackground)
                #if os(macOS)
                .background { MacWindowDragHandle() }
                #endif

            splitPaneNavBar
            splitPaneContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var splitPaneTabBar: some View {
        let tabs = splitPane?.tabs ?? []
        let activeID = splitPane?.activeTabID ?? ""
        return paneTabBar(
            tabs: tabs,
            activeTabID: activeID,
            onSelect: { tab in
                if var pane = splitPane {
                    pane.activeTabID = tab.id
                    splitPane = pane
                }
            },
            onClose: closeSplitPaneTab,
            onAddTab: addSplitPaneTab,
            showsPaneGroupIcon: true,
            showsTrailingChrome: showsSplitPaneTrailingChrome,
            leading: { EmptyView() }
        )
    }

    private var splitPaneNavBar: some View {
        let tab = splitPane?.activeTab
        return HStack(spacing: 0) {
            HStack(spacing: 14) {
                chromeIconButton("chevron.left", tip: "Back", isEnabled: false)
                chromeIconButton("chevron.right", tip: "Forward", isEnabled: false)
            }
            .frame(width: 72, alignment: .leading)

            Text(workspace.documentTitle(for: tab))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                if let tab, let fileID = tab.fileID {
                    Button {
                        workspace.presentBookmarkEditor(for: fileID)
                    } label: {
                        Image(systemName: workspace.isBookmarked(fileID) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                workspace.isBookmarked(fileID)
                                    ? AppColors.selectionStroke
                                    : AppColors.textSecondary
                            )
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(workspace.isBookmarked(fileID) ? "Edit bookmark" : "Add bookmark")

                    if tab.kind == .canvas {
                        CanvasDocumentOptionsMenu(
                            workspace: workspace,
                            canvasStore: canvasDocuments.store(for: fileID),
                            fileID: fileID,
                            splitLayout: splitLayoutBinding,
                            sidebarVisible: $sidebarVisible,
                            sidebarPanel: $sidebarPanel
                        )
                    } else if tab.kind == .note {
                        NoteDocumentOptionsMenu(
                            workspace: workspace,
                            fileID: fileID,
                            isReading: $splitPaneIsReading,
                            splitLayout: splitLayoutBinding,
                            sidebarVisible: $sidebarVisible,
                            sidebarPanel: $sidebarPanel,
                            showFindBar: $splitPaneShowFindBar
                        )
                    }
                }
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(AppColors.canvasBackground)
    }

    @ViewBuilder
    private var splitPaneContent: some View {
        let tab = splitPane?.activeTab
        switch tab?.kind {
        case .canvas:
            if let fileID = tab?.fileID {
                InfiniteCanvasView(
                    store: canvasDocuments.store(for: fileID),
                    workspace: workspace,
                    sidebarVisible: $sidebarVisible,
                    sidebarPanel: $sidebarPanel,
                    documentTitle: workspace.documentTitle(for: tab),
                    vaultURL: workspace.activeVaultURL,
                    independentCamera: true,
                    persistsCamera: false
                )
                .id("\(fileID)-splitpane")
            }
        case .note:
            if let fileID = tab?.fileID {
                NoteEditorView(
                    workspace: workspace,
                    fileID: fileID,
                    isReading: $splitPaneIsReading,
                    splitLayout: .constant(.none),
                    showFindBar: $splitPaneShowFindBar
                )
                .id("\(fileID)-splitpane")
            }
        case .graph:
            GraphView(workspace: workspace)
        case .newTab, .none:
            VStack(spacing: 10) {
                newTabPill("Go to file") {
                    goToFileTargetsSplitPane = true
                    showGoToFile = true
                }
                newTabPill("Close") {
                    if let id = splitPane?.activeTabID {
                        closeSplitPaneTab(id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.canvasBackground)
        }
    }

    #if os(macOS)
    private var macShell: some View {
        ZStack {
            shellLayout

            if workspace.isVaultManagerOpen {
                VaultManagerView(workspace: workspace)
                    .zIndex(10)
                    .transition(.opacity)
            }

            if workspace.isHelpOpen {
                DreftHelpView(workspace: workspace)
                    .zIndex(10)
                    .transition(.opacity)
            }

            if let bookmarkFileID = workspace.bookmarkEditorFileID {
                AddBookmarkSheet(workspace: workspace, fileID: bookmarkFileID)
                    .zIndex(15)
                    .transition(.opacity)
            }

            if showGoToFile {
                GoToFileSheet(
                    workspace: workspace,
                    isPresented: $showGoToFile,
                    replacingTabID: goToFileTargetsSplitPane ? nil : (activeTab?.kind == .newTab ? activeTab?.id : nil),
                    onFileSelected: goToFileTargetsSplitPane ? { openInSplitPane($0) } : nil
                )
                .zIndex(20)
                .transition(.opacity)
                .onDisappear { goToFileTargetsSplitPane = false }
            }
        }
        .animation(.easeOut(duration: 0.15), value: workspace.isVaultManagerOpen)
        .animation(.easeOut(duration: 0.15), value: workspace.isHelpOpen)
        .animation(.easeOut(duration: 0.15), value: workspace.bookmarkEditorFileID != nil)
        .animation(.easeOut(duration: 0.12), value: showGoToFile)
        .background(MacWindowChromeConfigurator())
        .background(AppColors.canvasBackground)
        .foregroundStyle(AppColors.textPrimary)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear(perform: bootstrapShellIfNeeded)
        .onChange(of: workspace.activeTabID) { _, _ in
            noteIsReading = false
            noteSplitLayout = .none
            showNoteFindBar = false
        }
        .onChange(of: workspace.activeVaultID) { _, _ in
            splitPane = nil
        }
        .onChange(of: workspace.selectedFileID) { _, _ in
            if workspace.activeTab?.kind == .note {
                noteIsReading = false
                noteSplitLayout = .none
                showNoteFindBar = false
            }
        }
        .background {
            Button("") { showGoToFile = true }
                .keyboardShortcut("o", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }
    #endif

    #if os(iOS)
    private var iosShell: some View {
        ZStack {
            shellLayout

            if workspace.isVaultManagerOpen {
                VaultManagerView(workspace: workspace)
                    .zIndex(10)
                    .transition(.opacity)
            }

            if workspace.isHelpOpen {
                DreftHelpView(workspace: workspace)
                    .zIndex(10)
                    .transition(.opacity)
            }

            if let bookmarkFileID = workspace.bookmarkEditorFileID {
                AddBookmarkSheet(workspace: workspace, fileID: bookmarkFileID)
                    .zIndex(15)
                    .transition(.opacity)
            }

            if showGoToFile {
                GoToFileSheet(
                    workspace: workspace,
                    isPresented: $showGoToFile,
                    replacingTabID: goToFileTargetsSplitPane ? nil : (activeTab?.kind == .newTab ? activeTab?.id : nil),
                    onFileSelected: goToFileTargetsSplitPane ? { openInSplitPane($0) } : nil
                )
                .zIndex(20)
                .transition(.opacity)
                .onDisappear { goToFileTargetsSplitPane = false }
            }
        }
        .background(AppColors.canvasBackground)
        .foregroundStyle(AppColors.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateStageManagerInset(from: geo) }
                    .onChange(of: geo.size) { _, _ in
                        updateStageManagerInset(from: geo)
                    }
                    .onChange(of: geo.frame(in: .global).minX) { _, _ in
                        updateStageManagerInset(from: geo)
                    }
            }
        }
        .onAppear(perform: bootstrapShellIfNeeded)
        .onChange(of: workspace.activeTabID) { _, _ in
            noteIsReading = false
            noteSplitLayout = .none
            showNoteFindBar = false
        }
        .onChange(of: workspace.activeVaultID) { _, _ in
            splitPane = nil
        }
        .onChange(of: workspace.selectedFileID) { _, newValue in
            if workspace.activeTab?.kind == .note {
                noteIsReading = false
                noteSplitLayout = .none
                showNoteFindBar = false
            }
            if usesFloatingSidebar && !ipadSidebarPinned,
               let id = newValue,
               let file = workspace.files.first(where: { $0.id == id }),
               file.kind != .folder {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarVisible = false
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: workspace.isVaultManagerOpen)
        .animation(.easeOut(duration: 0.15), value: workspace.isHelpOpen)
        .animation(.easeOut(duration: 0.15), value: workspace.bookmarkEditorFileID != nil)
        .animation(.easeOut(duration: 0.12), value: showGoToFile)
        .background {
            Button("") { showGoToFile = true }
                .keyboardShortcut("o", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }
    #endif

    // MARK: - Tab bar (Chrome-like + Obsidian mobile chrome)

    private let tabMaxWidth: CGFloat = 200
    private let tabMinWidth: CGFloat = 96
    private let singleTabWidth: CGFloat = 180

    private var tabBar: some View {
        paneTabBar(
            tabs: workspace.tabs,
            activeTabID: workspace.activeTabID,
            onSelect: { tab in
                workspace.activeTabID = tab.id
                workspace.selectedFileID = tab.fileID
            },
            onClose: { workspace.closeTab($0) },
            onAddTab: workspace.addTab,
            showsPaneGroupIcon: true,
            showsTrailingChrome: showsMainPaneTrailingChrome,
            leading: { tabBarLeading }
        )
    }

    /// Right-sidebar toggle lives on the trailing editor pane when split right.
    private var showsMainPaneTrailingChrome: Bool {
        guard let pane = splitPane else { return true }
        return pane.orientation == .down
    }

    private var showsSplitPaneTrailingChrome: Bool {
        splitPane?.orientation == .right
    }

    private func paneTabBar<Leading: View>(
        tabs: [WorkspaceTab],
        activeTabID: String,
        onSelect: @escaping (WorkspaceTab) -> Void,
        onClose: @escaping (String) -> Void,
        onAddTab: @escaping () -> Void,
        showsPaneGroupIcon: Bool,
        showsTrailingChrome: Bool,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 0) {
            leading()

            if showsPaneGroupIcon {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .padding(.trailing, 2)
            }

            GeometryReader { geo in
                let trailingSlot: CGFloat = showsTrailingChrome ? 56 : 28
                let plusSlot: CGFloat = 34
                let available = max(0, geo.size.width - plusSlot - trailingSlot)
                let count = max(tabs.count, 1)
                let width = tabs.count > 1
                    ? min(tabMaxWidth, max(tabMinWidth, available / CGFloat(count)))
                    : singleTabWidth
                let tabsWidth = min(available, CGFloat(tabs.count) * width)
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                                if index > 0 {
                                    paneTabSeparator(
                                        before: tabs[index - 1],
                                        after: tab,
                                        activeTabID: activeTabID
                                    )
                                }
                                paneTabButton(
                                    tab,
                                    isActive: tab.id == activeTabID,
                                    onSelect: { onSelect(tab) },
                                    onClose: { onClose(tab.id) }
                                )
                                .frame(width: width)
                            }
                        }
                    }
                    .frame(width: tabsWidth)
                    .padding(.leading, 4)

                    Button(action: onAddTab) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
                    .help("New tab")

                    Spacer(minLength: 0)
                }
            }

            paneTabListMenu(tabs: tabs, activeTabID: activeTabID, onSelect: onSelect)

            if showsTrailingChrome {
                chromeIconButton(
                    "sidebar.right",
                    tip: rightSidebarVisible ? "Collapse right sidebar" : "Expand right sidebar",
                    isActive: rightSidebarVisible
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        rightSidebarVisible.toggle()
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: AppColors.chromeRowHeight)
    }

    @ViewBuilder
    private func paneTabSeparator(
        before: WorkspaceTab,
        after: WorkspaceTab,
        activeTabID: String
    ) -> some View {
        if before.id != activeTabID && after.id != activeTabID {
            Rectangle()
                .fill(AppColors.border)
                .frame(width: 1, height: 16)
                .frame(maxHeight: .infinity, alignment: .center)
        } else {
            Color.clear.frame(width: 1)
        }
    }

    private func paneTabButton(
        _ tab: WorkspaceTab,
        isActive: Bool,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            tabIcon(for: tab.kind)
            Text(tab.title)
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: AppColors.chromeRowHeight - 2)
        .shellTabChrome(isActive: isActive)
        .contentShape(ShellTabShape())
        .onTapGesture(perform: onSelect)
    }

    private func paneTabListMenu(
        tabs: [WorkspaceTab],
        activeTabID: String,
        onSelect: @escaping (WorkspaceTab) -> Void
    ) -> some View {
        Menu {
            ForEach(tabs) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    if tab.id == activeTabID {
                        Label(tab.title, systemImage: "checkmark")
                    } else {
                        Text(tab.title)
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("List tabs")
    }

    /// Layout: [Stage Manager window-control inset] → sidebar toggle → tabs.
    @ViewBuilder
    private var tabBarLeading: some View {
        #if os(iOS)
        if usesDesktopChrome {
            Color.clear
                .frame(width: stageManagerLeadingInsetValue)
            chromeIconButton(
                "sidebar.left",
                tip: sidebarVisible ? "Hide sidebar" : "Show sidebar",
                isActive: sidebarVisible
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarVisible.toggle()
                }
            }
            .frame(width: 28)
            .padding(.trailing, 6)
        }
        #else
        if !sidebarVisible && usesDesktopChrome {
            Color.clear
                .frame(width: 28)
            chromeIconButton("sidebar.left", tip: "Expand sidebar") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarVisible = true
                }
            }
            .frame(width: 28)
        }
        #endif
    }

    /// Clearance for Stage Manager traffic lights when the app is windowed on iPad.
    private var stageManagerLeadingInsetValue: CGFloat {
        #if os(iOS)
        stageManagerLeadingInset
        #else
        0
        #endif
    }

    #if os(iOS)
    private func updateStageManagerInset(from geo: GeometryProxy) {
        let frame = geo.frame(in: .global)
        let screen = UIScreen.main.bounds
        let windowed = frame.minX > 8 || abs(frame.width - screen.width) > 16
        let next: CGFloat = windowed ? 70 : 0
        if stageManagerLeadingInset != next {
            stageManagerLeadingInset = next
        }
    }
    #endif

    @ViewBuilder
    private func tabIcon(for kind: WorkspaceTabKind) -> some View {
        switch kind {
        case .canvas:
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
        case .note:
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
        case .graph:
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
        case .newTab:
            EmptyView()
        }
    }

    // MARK: - Document nav (back / title / more)

    private var documentNavBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                #if os(iOS)
                if !usesDesktopChrome {
                    chromeIconButton("sidebar.left", tip: "Toggle sidebar") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sidebarVisible.toggle()
                        }
                    }
                }
                #endif
                chromeIconButton(
                    "chevron.left",
                    tip: "Back",
                    isEnabled: workspace.canNavigateBack
                ) {
                    workspace.goBack()
                }
                chromeIconButton(
                    "chevron.right",
                    tip: "Forward",
                    isEnabled: workspace.canNavigateForward
                ) {
                    workspace.goForward()
                }
            }
            .frame(width: documentNavLeadingWidth, alignment: .leading)

            Text(documentTitle)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                if activeTab?.kind == .note, let fileID = activeTab?.fileID {
                    ObsidianViewModeButton(isReading: $noteIsReading) {
                        noteSplitLayout = .none
                    }
                    NoteDocumentOptionsMenu(
                        workspace: workspace,
                        fileID: fileID,
                        isReading: $noteIsReading,
                        splitLayout: splitLayoutBinding,
                        sidebarVisible: $sidebarVisible,
                        sidebarPanel: $sidebarPanel,
                        showFindBar: $showNoteFindBar
                    )
                }
                if activeTab?.kind == .canvas, let fileID = activeTab?.fileID {
                    Button {
                        workspace.presentBookmarkEditor(for: fileID)
                    } label: {
                        Image(systemName: workspace.isBookmarked(fileID) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                workspace.isBookmarked(fileID)
                                    ? AppColors.selectionStroke
                                    : AppColors.textSecondary
                            )
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(workspace.isBookmarked(fileID) ? "Edit bookmark" : "Add bookmark")

                    CanvasDocumentOptionsMenu(
                        workspace: workspace,
                        canvasStore: canvasDocuments.store(for: fileID),
                        fileID: fileID,
                        splitLayout: splitLayoutBinding,
                        sidebarVisible: $sidebarVisible,
                        sidebarPanel: $sidebarPanel
                    )
                }
            }
            .frame(width: documentNavTrailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(AppColors.canvasBackground)
    }

    private var documentNavLeadingWidth: CGFloat {
        #if os(iOS)
        100
        #else
        72
        #endif
    }

    private var documentNavTrailingWidth: CGFloat {
        #if os(iOS)
        120
        #else
        96
        #endif
    }

    private func chromeIconButton(
        _ name: String,
        tip: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    isEnabled
                        ? (isActive ? AppColors.textPrimary : AppColors.textSecondary)
                        : AppColors.textMuted.opacity(0.35)
                )
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? AppColors.sidebarSelection.opacity(0.85) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(tip)
    }

    // MARK: - Content

    private var canvasArea: some View {
        Group {
            switch activeTab?.kind {
            case .canvas:
                let documentID = activeTab?.fileID ?? activeTab?.id ?? "default"
                let canvasStore = canvasDocuments.store(for: documentID)
                canvasDocumentContent(store: canvasStore, documentID: documentID)
                .onAppear {
                    canvasStore.setVaultFiles(workspace.files)
                }
                .onChange(of: workspace.files) { _, files in
                    canvasDocuments.syncVaultFiles(files)
                }
                .onChange(of: workspace.activeTabID) { _, _ in
                    if activeTab?.kind == .canvas {
                        canvasStore.setVaultFiles(workspace.files)
                    }
                }
            case .note:
                if let fileID = activeTab?.fileID {
                    NoteEditorView(
                        workspace: workspace,
                        fileID: fileID,
                        isReading: $noteIsReading,
                        splitLayout: $noteSplitLayout,
                        showFindBar: $showNoteFindBar
                    )
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColors.canvasBackground)
                }
            case .graph:
                GraphView(workspace: workspace)
                    .onAppear {
                        workspace.flushNotesForGraph()
                    }
            case .newTab, .none:
                newTabPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func canvasDocumentContent(store: CanvasStore, documentID: String) -> some View {
        InfiniteCanvasView(
            store: store,
            workspace: workspace,
            sidebarVisible: $sidebarVisible,
            sidebarPanel: $sidebarPanel,
            documentTitle: documentTitle,
            vaultURL: workspace.activeVaultURL
        )
        .id("\(documentID)-primary")
    }

    private var newTabPlaceholder: some View {
        VStack(spacing: 10) {
            newTabPill("Create new note") {
                workspace.createNote()
            }
            newTabPill("Go to file") {
                showGoToFile = true
            }
            newTabPill("Close") {
                if let tab = activeTab { workspace.closeTab(tab.id) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.canvasBackground)
    }

    private func newTabPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.pillButtonText)
                .frame(minWidth: 180)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(AppColors.pillButtonFill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WorkspaceShellView()
        .frame(width: 1200, height: 800)
}

private extension View {
    func vaultErrorAlert(workspace: WorkspaceStore) -> some View {
        alert(
            workspace.vaultAlert?.title ?? "Vault error",
            isPresented: Binding(
                get: { workspace.vaultAlert != nil },
                set: { isPresented in
                    if !isPresented {
                        workspace.clearVaultAlert()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                workspace.clearVaultAlert()
            }
        } message: {
            Text(workspace.vaultAlert?.message ?? "")
        }
    }
}

// MARK: - Shared chrome

/// Full-width divider under the unified top chrome row (tab bar + sidebar switcher).
private struct ChromeRowHairline: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: AppColors.chromeRowHeight - 1)
            ShellHairline()
        }
        .allowsHitTesting(false)
    }
}

extension WorkspaceShellView {
    fileprivate var chromeRowHairline: some View {
        ChromeRowHairline()
    }
}

struct ShellHairline: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(height: 1)
    }
}

struct ShellVerticalHairline: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}

private struct ShellTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 10
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private extension View {
    func shellTabChrome(isActive: Bool) -> some View {
        self
            .background {
                if isActive {
                    ShellTabShape()
                        .fill(AppColors.canvasBackground)
                        .shadow(color: Color.black.opacity(0.06), radius: 1, y: -0.5)
                }
            }
            .clipShape(ShellTabShape())
    }
}

#if os(macOS)
import AppKit

/// Hides the system title and lets custom tab chrome sit flush with the window top (Obsidian-style).
private struct MacWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
    }
}

/// Drag handle for the custom title bar — only the top chrome row moves the window.
private struct MacWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> MacWindowDragView {
        MacWindowDragView()
    }

    func updateNSView(_ nsView: MacWindowDragView, context: Context) {}
}

private final class MacWindowDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
#endif
