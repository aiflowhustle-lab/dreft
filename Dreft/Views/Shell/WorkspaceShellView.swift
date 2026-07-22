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
    /// Nested Obsidian-style split tree; nil means a single root pane only.
    @State private var splitRoot: EditorSplitNode?
    @State private var auxiliaryPanes: [String: EditorAuxiliaryPane] = [:]
    @State private var paneUIState: [String: EditorPaneUIState] = [:]
    @State private var focusedPaneID = EditorSplitTree.rootPaneID
    /// When set, Go-to-file opens into this pane id.
    @State private var goToFileTargetPaneID: String?
    @AppStorage("sidebarWidth") private var sidebarWidthStorage = SidebarLayout.defaultWidth
    @State private var sidebarWidth = SidebarLayout.defaultWidth
    @State private var isResizingSidebar = false
    #if os(iOS)
    @State private var usesStageManagerTopBand = false
    @State private var iPadLayoutDebounceTask: Task<Void, Never>?
    @State private var vaultFolderPickerPurpose: VaultFolderPickerPurpose?
    @State private var vaultFolderPickerHandler: ((URL, VaultFolderPickerPurpose) -> Void)?
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
        workspace.checkActiveVaultAccessibility()
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
            if phase == .inactive || phase == .background {
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

    /// On iPad the sidebar always floats over the canvas (regular + compact width).
    private var usesFloatingSidebar: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var iconRailTopInset: CGFloat {
        #if os(macOS)
        sidebarVisible ? AppColors.macTrafficLightInset : AppColors.chromeRowHeight
        #else
        8
        #endif
    }

    #if os(macOS)
    private var macIconRailWidth: CGFloat { 40 }

    private var macLeftmostPaneID: String {
        if let splitRoot, let leftmost = EditorSplitTree.leftmostPane(in: splitRoot) {
            return leftmost
        }
        return EditorSplitTree.rootPaneID
    }

    /// Leftmost pane tab bar may need a small inset past the icon rail to clear traffic lights.
    private func macPaneTrafficLightClearance(for paneID: String) -> CGFloat {
        guard paneShowsLeadingChrome(paneID), !sidebarVisible else { return 0 }
        return max(0, AppColors.macTabBarTrafficLightClearance - macIconRailWidth)
    }
    #endif

    private var tabBarSurfaceColor: Color {
        AppColors.tabBarBackground
    }

    private var documentBookmarkIconSize: CGFloat { 16 }
    private var documentBookmarkFrameSize: CGFloat { 28 }

    private var shellLayout: some View {
        HStack(spacing: 0) {
            #if os(macOS)
            if iconRailVisible && usesDesktopChrome {
                IconRailView(
                    sidebarVisible: $sidebarVisible,
                    isGraphActive: focusedPaneActiveTab?.kind == .graph,
                    isCanvasActive: focusedPaneActiveTab?.kind == .canvas,
                    onGoToFile: openGoToFileInFocusedPane,
                    onOpenGraph: openGraphInFocusedPane,
                    onCreateCanvas: createCanvasInFocusedPane,
                    onCreateNote: createNoteInFocusedPane,
                    onManageVaults: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            workspace.isVaultManagerOpen = true
                        }
                    },
                    contentTopInset: iconRailTopInset
                )
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                ShellVerticalHairline()
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
            if usesDesktopChrome && splitRoot == nil {
                tabBarSurfaceColor
                    .frame(height: tabBarChromeHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        #if os(macOS)
        .overlay(alignment: .top) {
            if usesDesktopChrome && splitRoot == nil {
                chromeRowHairline
            }
        }
        #endif
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
        if sidebarVisible {
            GeometryReader { geo in
                let panelWidth = floatingSidebarPanelWidth(in: geo)
                ZStack(alignment: .topLeading) {
                    if !ipadSidebarPinned || !usesDesktopChrome {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { dismissFloatingSidebar() }
                            .gesture(sidebarDismissDragGesture)
                    }

                    HStack(alignment: .top, spacing: 6) {
                        if usesDesktopChrome {
                            IPadIconRail(
                                sidebarVisible: $sidebarVisible,
                                sidebarPanel: $sidebarPanel,
                                isGraphActive: focusedPaneActiveTab?.kind == .graph,
                                isCanvasActive: focusedPaneActiveTab?.kind == .canvas,
                                onGoToFile: openGoToFileInFocusedPane,
                                onOpenGraph: openGraphInFocusedPane,
                                onCreateCanvas: createCanvasInFocusedPane,
                                onCreateNote: createNoteInFocusedPane,
                                onManageVaults: {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        workspace.isVaultManagerOpen = true
                                    }
                                },
                                onSwipeToDismiss: (ipadSidebarPinned && usesDesktopChrome) ? nil : dismissFloatingSidebar
                            )
                        }
                        IPadFloatingSidebar(
                            workspace: workspace,
                            sidebarVisible: $sidebarVisible,
                            sidebarPanel: $sidebarPanel,
                            isPinned: $ipadSidebarPinned,
                            panelWidth: panelWidth,
                            onOpenDocument: openDocumentInFocusedPane,
                            onSwipeToDismiss: (ipadSidebarPinned && usesDesktopChrome) ? nil : dismissFloatingSidebar
                        )
                    }
                    .padding(.leading, 6)
                    .padding(.top, max(10, geo.safeAreaInsets.top))
                    .padding(.bottom, 10)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    /// Keep sidebar width stable when the keyboard opens (don't shrink with safe-area inset).
    private func floatingSidebarPanelWidth(in geo: GeometryProxy) -> CGFloat {
        if horizontalSizeClass == .regular {
            return IPadShellMetrics.sidebarWidth
        }
        return min(
            IPadShellMetrics.sidebarWidth,
            max(280, geo.size.width - (usesDesktopChrome ? IPadShellMetrics.railWidth + 18 : 16))
        )
    }

    /// Swipe left on the canvas/scrim or sidebar panel to close the floating sidebar (Obsidian-style).
    private var sidebarDismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard !(ipadSidebarPinned && usesDesktopChrome) else { return }
                if value.translation.width < -40,
                   abs(value.translation.width) > abs(value.translation.height) * 1.2 {
                    dismissFloatingSidebar()
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
                activePanel: sidebarPanel,
                onOpenDocument: openDocumentInFocusedPane
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
                                        openDocumentInFocusedPane(file)
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
            if let splitRoot {
                splitNodeView(splitRoot)
            } else {
                editorPane(paneID: EditorSplitTree.rootPaneID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.canvasBackground)
        .onChange(of: workspace.files) { _, files in
            canvasDocuments.syncVaultFiles(files)
        }
        #if os(iOS)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        scheduleIPadWindowLayoutUpdate(size: geo.size)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        scheduleIPadWindowLayoutUpdate(size: newSize)
                    }
            }
        }
        #endif
    }

    private func splitNodeView(_ node: EditorSplitNode) -> AnyView {
        switch node {
        case .pane(let paneID):
            return AnyView(editorPane(paneID: paneID))
        case .split(let axis, let ratio, let first, let second):
            switch axis {
            case .horizontal:
                return AnyView(
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            splitNodeView(first)
                                .frame(width: geo.size.width * ratio)
                            ShellVerticalHairline()
                            splitNodeView(second)
                                .frame(width: geo.size.width * (1 - ratio))
                        }
                    }
                )
            case .vertical:
                return AnyView(
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            splitNodeView(first)
                                .frame(height: geo.size.height * ratio)
                            ShellHairline()
                            splitNodeView(second)
                                .frame(height: geo.size.height * (1 - ratio))
                        }
                    }
                )
            }
        }
    }

    private func editorPane(paneID: String) -> some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // Tab row renders in a per-pane overlay (Obsidian-style, one tab bar per editor group).
            Color.clear.frame(height: tabBarRowHeight)
            #else
            iPadWindowedTabChrome {
                paneTabBarContent(paneID: paneID)
            }
            .frame(height: tabBarChromeHeight)
            .background(tabBarSurfaceColor)
            #endif

            paneNavBar(paneID: paneID)
            paneContent(paneID: paneID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture {
            focusedPaneID = paneID
        }
        #if os(macOS)
        .overlay(alignment: .top) {
            macPaneTabBarChrome(paneID: paneID)
                .zIndex(5)
        }
        #endif
    }

    #if os(macOS)
    private func macPaneTabBarChrome(paneID: String) -> some View {
        iPadWindowedTabChrome {
            paneTabBarContent(paneID: paneID)
        }
        .frame(height: tabBarRowHeight)
        .background(tabBarSurfaceColor)
        .overlay(alignment: .bottom) {
            ShellHairline()
        }
        .background(alignment: .bottom) {
            if paneID == macLeftmostPaneID {
                MacWindowDragHandle()
                    .frame(height: tabBarRowHeight)
            }
        }
    }
    #endif

    /// Tab row height — includes Stage Manager band on iPad when windowed.
    private var tabBarChromeHeight: CGFloat {
        #if os(iOS)
        if usesDesktopChrome && usesStageManagerTopBand {
            return AppColors.iPadStageManagerTopBandHeight + tabBarRowHeight
        }
        if usesDesktopChrome {
            return tabBarRowHeight
        }
        #endif
        return tabBarRowHeight
    }

    private var tabBarRowHeight: CGFloat {
        #if os(iOS)
        if usesDesktopChrome { return AppColors.iPadTabBarRowHeight }
        #endif
        return AppColors.chromeRowHeight
    }

    #if os(iOS)
    private var iPadSidebarToggleIconSize: CGFloat { 18 }
    private var iPadSidebarToggleFrameSize: CGFloat { AppColors.minimumTouchTarget }
    private var iPadSidebarToggleSlotWidth: CGFloat { AppColors.minimumTouchTarget + 4 }
    #elseif os(macOS)
    /// Tab-bar sidebar toggles only (+40% vs default chrome icons).
    private var macSidebarToggleIconSize: CGFloat { 18 }
    private var macSidebarToggleFrameSize: CGFloat { 31 }
    private var macSidebarToggleSlotWidth: CGFloat { 39 }
    #endif

    private var sidebarToggleIconSize: CGFloat {
        #if os(iOS)
        usesDesktopChrome ? iPadSidebarToggleIconSize : 13
        #elseif os(macOS)
        macSidebarToggleIconSize
        #else
        13
        #endif
    }

    private var sidebarToggleFrameSize: CGFloat {
        #if os(iOS)
        usesDesktopChrome ? iPadSidebarToggleFrameSize : 22
        #elseif os(macOS)
        macSidebarToggleFrameSize
        #else
        22
        #endif
    }

    private var sidebarToggleLeadingSlotWidth: CGFloat {
        #if os(macOS)
        macSidebarToggleSlotWidth
        #else
        28
        #endif
    }

    private var sidebarToggleTrailingSlot: CGFloat {
        #if os(iOS)
        usesDesktopChrome ? iPadSidebarToggleSlotWidth + 8 : 56
        #elseif os(macOS)
        78
        #else
        56
        #endif
    }

    // MARK: - Split tree (nested Obsidian-style panes)

    private func paneTabs(for paneID: String) -> [WorkspaceTab] {
        if paneID == EditorSplitTree.rootPaneID {
            return workspace.tabs
        }
        return auxiliaryPanes[paneID]?.tabs ?? []
    }

    private func paneActiveTabID(for paneID: String) -> String {
        if paneID == EditorSplitTree.rootPaneID {
            return workspace.activeTabID
        }
        return auxiliaryPanes[paneID]?.activeTabID ?? ""
    }

    private func paneActiveTab(for paneID: String) -> WorkspaceTab? {
        let tabs = paneTabs(for: paneID)
        let activeID = paneActiveTabID(for: paneID)
        return tabs.first { $0.id == activeID } ?? tabs.first
    }

    private func paneUI(for paneID: String) -> EditorPaneUIState {
        if paneID == EditorSplitTree.rootPaneID {
            return EditorPaneUIState(isReading: noteIsReading, showFindBar: showNoteFindBar)
        }
        return paneUIState[paneID] ?? EditorPaneUIState()
    }

    private func setPaneUI(_ paneID: String, _ state: EditorPaneUIState) {
        guard paneID != EditorSplitTree.rootPaneID else {
            noteIsReading = state.isReading
            showNoteFindBar = state.showFindBar
            return
        }
        paneUIState[paneID] = state
    }

    private func splitPaneActions(for paneID: String) -> (() -> Void, () -> Void) {
        (
            { splitPane(paneID, axis: .horizontal) },
            { splitPane(paneID, axis: .vertical) }
        )
    }

    private func splitPane(_ paneID: String, axis: EditorSplitAxis) {
        focusedPaneID = paneID
        let currentRoot = splitRoot ?? .pane(EditorSplitTree.rootPaneID)
        guard let (updatedRoot, newPaneID) = EditorSplitTree.splitPane(paneID, axis: axis, in: currentRoot) else {
            return
        }

        let sourceTab = paneActiveTab(for: paneID) ?? WorkspaceTab(
            id: EditorSplitTree.newTabID(),
            title: "New tab",
            kind: .newTab,
            fileID: nil
        )
        var newTab = sourceTab
        newTab.id = EditorSplitTree.newTabID()

        withAnimation(.easeInOut(duration: 0.18)) {
            splitRoot = updatedRoot
            auxiliaryPanes[newPaneID] = EditorAuxiliaryPane(
                tabs: [newTab],
                activeTabID: newTab.id
            )
            paneUIState[newPaneID] = EditorPaneUIState()
            focusedPaneID = newPaneID
        }
    }

    private func collapseSplitIfNeeded() {
        guard let splitRoot else { return }
        let paneIDs = EditorSplitTree.allPaneIDs(in: splitRoot)
        let remainingAux = paneIDs.filter { $0 != EditorSplitTree.rootPaneID }
        if remainingAux.isEmpty {
            withAnimation(.easeInOut(duration: 0.18)) {
                self.splitRoot = nil
                auxiliaryPanes = [:]
                paneUIState = [:]
            }
        }
    }

    private func closePaneTab(paneID: String, tabID: String) {
        focusedPaneID = paneID
        if paneID == EditorSplitTree.rootPaneID {
            workspace.closeTab(tabID)
            return
        }

        guard var pane = auxiliaryPanes[paneID] else { return }
        pane.tabs.removeAll { $0.id == tabID }
        if pane.tabs.isEmpty {
            removeAuxiliaryPane(paneID)
            return
        }
        if pane.activeTabID == tabID {
            pane.activeTabID = pane.tabs[0].id
        }
        auxiliaryPanes[paneID] = pane
    }

    private func closeAllPaneTabs(paneID: String) {
        focusedPaneID = paneID
        if paneID == EditorSplitTree.rootPaneID {
            workspace.closeAllTabs()
            return
        }
        removeAuxiliaryPane(paneID)
    }

    private func addPaneTab(paneID: String) {
        focusedPaneID = paneID
        let tab = WorkspaceTab(
            id: EditorSplitTree.newTabID(),
            title: "New tab",
            kind: .newTab,
            fileID: nil
        )
        if paneID == EditorSplitTree.rootPaneID {
            workspace.tabs.append(tab)
            workspace.activeTabID = tab.id
            return
        }
        guard var pane = auxiliaryPanes[paneID] else { return }
        pane.tabs.append(tab)
        pane.activeTabID = tab.id
        auxiliaryPanes[paneID] = pane
    }

    private func selectPaneTab(paneID: String, tab: WorkspaceTab) {
        focusedPaneID = paneID
        if paneID == EditorSplitTree.rootPaneID {
            workspace.activeTabID = tab.id
            workspace.selectedFileID = tab.fileID
            return
        }
        guard var pane = auxiliaryPanes[paneID] else { return }
        pane.activeTabID = tab.id
        auxiliaryPanes[paneID] = pane
        workspace.selectedFileID = tab.fileID
    }

    private func removeAuxiliaryPane(_ paneID: String) {
        guard paneID != EditorSplitTree.rootPaneID else { return }
        auxiliaryPanes.removeValue(forKey: paneID)
        paneUIState.removeValue(forKey: paneID)
        if let splitRoot {
            if let collapsed = EditorSplitTree.removePane(paneID, from: splitRoot) {
                self.splitRoot = collapsed == .pane(EditorSplitTree.rootPaneID) ? nil : collapsed
            } else {
                self.splitRoot = nil
            }
        }
        if focusedPaneID == paneID {
            focusedPaneID = EditorSplitTree.rootPaneID
        }
        collapseSplitIfNeeded()
    }

    private func openDocumentInFocusedPane(_ file: WorkspaceFileEntry) {
        switch file.kind {
        case .note, .canvas:
            openFileInPane(focusedPaneID, file: file)
        default:
            workspace.selectFile(file.id)
        }
    }

    private var goToFileReplacingTabID: String? {
        let paneID = goToFileTargetPaneID ?? focusedPaneID
        let tab = paneActiveTab(for: paneID)
        if tab?.kind == .newTab { return tab?.id }
        return paneActiveTabID(for: paneID)
    }

    private func handleGoToFileSelection(_ file: WorkspaceFileEntry) {
        let paneID = goToFileTargetPaneID ?? focusedPaneID
        openFileInPane(paneID, file: file)
    }

    private var focusedPaneActiveTab: WorkspaceTab? {
        paneActiveTab(for: focusedPaneID)
    }

    private func openGoToFileInFocusedPane() {
        goToFileTargetPaneID = focusedPaneID
        showGoToFile = true
    }

    private func openGraphInFocusedPane() {
        openGraphInPane(focusedPaneID)
    }

    private func createCanvasInFocusedPane() {
        guard let entry = workspace.createCanvas(autoNavigate: false) else { return }
        openFileInPane(focusedPaneID, file: entry)
    }

    private func createNoteInFocusedPane() {
        guard let entry = workspace.createNote(autoNavigate: false) else { return }
        openFileInPane(focusedPaneID, file: entry)
    }

    private func openGraphInPane(_ paneID: String) {
        focusedPaneID = paneID
        if paneID == EditorSplitTree.rootPaneID {
            if let existing = workspace.tabs.first(where: { $0.kind == .graph }) {
                workspace.activeTabID = existing.id
                return
            }
            let tab = WorkspaceTab(
                id: EditorSplitTree.newTabID(),
                title: "Graph view",
                kind: .graph,
                fileID: nil
            )
            replaceActiveTabInRoot(with: tab)
            return
        }

        guard var pane = auxiliaryPanes[paneID] else { return }
        if let existing = pane.tabs.first(where: { $0.kind == .graph }) {
            pane.activeTabID = existing.id
            auxiliaryPanes[paneID] = pane
            return
        }
        let tab = WorkspaceTab(
            id: EditorSplitTree.newTabID(),
            title: "Graph view",
            kind: .graph,
            fileID: nil
        )
        replaceActiveTab(in: &pane, with: tab)
        auxiliaryPanes[paneID] = pane
    }

    private func replaceActiveTabInRoot(with tab: WorkspaceTab) {
        if let index = workspace.tabs.firstIndex(where: { $0.id == workspace.activeTabID }) {
            workspace.tabs[index] = tab
        } else {
            workspace.tabs.append(tab)
        }
        workspace.activeTabID = tab.id
        if let fileID = tab.fileID {
            workspace.selectedFileID = fileID
        }
    }

    private func replaceActiveTab(in pane: inout EditorAuxiliaryPane, with tab: WorkspaceTab) {
        if let index = pane.tabs.firstIndex(where: { $0.id == pane.activeTabID }) {
            pane.tabs[index] = tab
        } else {
            pane.tabs.append(tab)
        }
        pane.activeTabID = tab.id
    }

    private func openFileInPane(_ paneID: String, file: WorkspaceFileEntry) {
        guard file.kind == .note || file.kind == .canvas else { return }
        focusedPaneID = paneID
        if paneID == EditorSplitTree.rootPaneID {
            if let existing = workspace.tabs.first(where: { $0.fileID == file.id }) {
                workspace.activeTabID = existing.id
                workspace.selectedFileID = file.id
                noteIsReading = false
                showNoteFindBar = false
                return
            }
            let tab = WorkspaceTab(
                id: EditorSplitTree.newTabID(),
                title: file.name,
                kind: file.kind == .canvas ? .canvas : .note,
                fileID: file.id
            )
            replaceActiveTabInRoot(with: tab)
            noteIsReading = false
            showNoteFindBar = false
            return
        }

        guard var pane = auxiliaryPanes[paneID] else { return }
        if let existing = pane.tabs.first(where: { $0.fileID == file.id }) {
            pane.activeTabID = existing.id
            auxiliaryPanes[paneID] = pane
            workspace.selectedFileID = file.id
            return
        }
        let tab = WorkspaceTab(
            id: EditorSplitTree.newTabID(),
            title: file.name,
            kind: file.kind == .canvas ? .canvas : .note,
            fileID: file.id
        )
        replaceActiveTab(in: &pane, with: tab)
        auxiliaryPanes[paneID] = pane
        paneUIState[paneID] = EditorPaneUIState()
        workspace.selectedFileID = file.id
    }

    private func paneShowsTrailingChrome(_ paneID: String) -> Bool {
        EditorSplitTree.paneShowsRightSidebarChrome(paneID, in: splitRoot)
    }

    private func paneShowsLeadingChrome(_ paneID: String) -> Bool {
        EditorSplitTree.paneShowsLeftSidebarChrome(paneID, in: splitRoot)
    }

    private func paneTabBarContent(paneID: String) -> some View {
        let tabs = paneTabs(for: paneID)
        let activeID = paneActiveTabID(for: paneID)
        return paneTabBar(
            tabs: tabs,
            activeTabID: activeID,
            onSelect: { selectPaneTab(paneID: paneID, tab: $0) },
            onClose: { closePaneTab(paneID: paneID, tabID: $0) },
            onCloseAll: { closeAllPaneTabs(paneID: paneID) },
            onAddTab: { addPaneTab(paneID: paneID) },
            showsTrailingChrome: paneShowsTrailingChrome(paneID),
            leading: {
                if paneShowsLeadingChrome(paneID) {
                    tabBarLeading(for: paneID)
                } else {
                    EmptyView()
                }
            }
        )
    }

    private func paneNavBar(paneID: String) -> some View {
        let tab = paneActiveTab(for: paneID)
        let splitActions = splitPaneActions(for: paneID)
        let isRoot = paneID == EditorSplitTree.rootPaneID

        return HStack(spacing: 0) {
            HStack(spacing: 14) {
                #if os(iOS)
                if paneShowsLeadingChrome(paneID), !usesDesktopChrome {
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
                    isEnabled: isRoot && workspace.canNavigateBack
                ) {
                    workspace.goBack()
                }
                chromeIconButton(
                    "chevron.right",
                    tip: "Forward",
                    isEnabled: isRoot && workspace.canNavigateForward
                ) {
                    workspace.goForward()
                }
            }
            .frame(width: documentNavLeadingWidth, alignment: .leading)

            Text(workspace.documentTitle(for: tab))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                if tab?.kind == .note, let fileID = tab?.fileID {
                    ObsidianViewModeButton(isReading: Binding(
                        get: { paneUI(for: paneID).isReading },
                        set: { newValue in
                            var state = paneUI(for: paneID)
                            state.isReading = newValue
                            if newValue { state.showFindBar = false }
                            setPaneUI(paneID, state)
                        }
                    )) {
                        if isRoot { noteSplitLayout = .none }
                    }
                    NoteDocumentOptionsMenu(
                        workspace: workspace,
                        fileID: fileID,
                        isReading: Binding(
                            get: { paneUI(for: paneID).isReading },
                            set: { newValue in
                                var state = paneUI(for: paneID)
                                state.isReading = newValue
                                setPaneUI(paneID, state)
                            }
                        ),
                        onSplitRight: splitActions.0,
                        onSplitDown: splitActions.1,
                        sidebarVisible: $sidebarVisible,
                        sidebarPanel: $sidebarPanel,
                        showFindBar: Binding(
                            get: { paneUI(for: paneID).showFindBar },
                            set: { newValue in
                                var state = paneUI(for: paneID)
                                state.showFindBar = newValue
                                if newValue { state.isReading = false }
                                setPaneUI(paneID, state)
                            }
                        )
                    )
                }
                if tab?.kind == .canvas, let fileID = tab?.fileID {
                    documentBookmarkButton(fileID: fileID)
                    CanvasDocumentOptionsMenu(
                        workspace: workspace,
                        canvasStore: canvasDocuments.store(for: fileID),
                        fileID: fileID,
                        onSplitRight: splitActions.0,
                        onSplitDown: splitActions.1,
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

    @ViewBuilder
    private func paneContent(paneID: String) -> some View {
        let tab = paneActiveTab(for: paneID)
        let isRoot = paneID == EditorSplitTree.rootPaneID

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
                    independentCamera: !isRoot,
                    persistsCamera: isRoot
                )
                .id("\(fileID)-\(paneID)")
                .onAppear {
                    canvasDocuments.store(for: fileID).setVaultFiles(workspace.files)
                }
            }
        case .note:
            if let fileID = tab?.fileID {
                NoteEditorView(
                    workspace: workspace,
                    fileID: fileID,
                    isReading: Binding(
                        get: { paneUI(for: paneID).isReading },
                        set: { newValue in
                            var state = paneUI(for: paneID)
                            state.isReading = newValue
                            setPaneUI(paneID, state)
                        }
                    ),
                    splitLayout: isRoot ? $noteSplitLayout : .constant(.none),
                    showFindBar: Binding(
                        get: { paneUI(for: paneID).showFindBar },
                        set: { newValue in
                            var state = paneUI(for: paneID)
                            state.showFindBar = newValue
                            setPaneUI(paneID, state)
                        }
                    )
                )
                .id("\(fileID)-\(paneID)")
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.canvasBackground)
            }
        case .graph:
            GraphView(workspace: workspace) { file in
                openFileInPane(paneID, file: file)
            }
                .onAppear {
                    if isRoot { workspace.flushNotesForGraph() }
                }
        case .newTab, .none:
            newTabPlaceholder(paneID: paneID)
        }
    }

    private func documentBookmarkButton(fileID: String) -> some View {
        Button {
            workspace.presentBookmarkEditor(for: fileID)
        } label: {
            Image(systemName: workspace.isBookmarked(fileID) ? "bookmark.fill" : "bookmark")
                .font(.system(size: documentBookmarkIconSize, weight: .medium))
                .foregroundStyle(
                    workspace.isBookmarked(fileID)
                        ? AppColors.selectionStroke
                        : AppColors.textSecondary
                )
                .frame(width: documentBookmarkFrameSize, height: documentBookmarkFrameSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(workspace.isBookmarked(fileID) ? "Edit bookmark" : "Add bookmark")
    }

    private func newTabPlaceholder(paneID: String) -> some View {
        VStack(spacing: 10) {
            newTabPill("Create new note") {
                workspace.createNote()
            }
            newTabPill("Go to file") {
                goToFileTargetPaneID = paneID
                showGoToFile = true
            }
            newTabPill("Close") {
                if let tab = paneActiveTab(for: paneID) {
                    closePaneTab(paneID: paneID, tabID: tab.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.canvasBackground)
    }

    #if os(macOS)
    private var macShell: some View {
        ZStack {
            shellLayout
                .animation(nil, value: workspace.isVaultManagerOpen)
                .animation(nil, value: workspace.isHelpOpen)
                .animation(nil, value: workspace.bookmarkEditorFileID != nil)
                .animation(nil, value: showGoToFile)

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
                    replacingTabID: goToFileReplacingTabID,
                    onFileSelected: handleGoToFileSelection
                )
                .zIndex(20)
                .transition(.opacity)
                .onDisappear { goToFileTargetPaneID = nil }
            }
        }
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
            splitRoot = nil
            auxiliaryPanes = [:]
            paneUIState = [:]
            focusedPaneID = EditorSplitTree.rootPaneID
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
                .animation(nil, value: workspace.isVaultManagerOpen)
                .animation(nil, value: workspace.isHelpOpen)
                .animation(nil, value: workspace.bookmarkEditorFileID != nil)
                .animation(nil, value: showGoToFile)

            if workspace.isVaultManagerOpen {
                VaultManagerView(
                    workspace: workspace,
                    onRequestFolderPicker: { purpose, handler in
                        vaultFolderPickerHandler = handler
                        vaultFolderPickerPurpose = purpose
                    }
                )
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
                    replacingTabID: goToFileReplacingTabID,
                    onFileSelected: handleGoToFileSelection
                )
                .zIndex(20)
                .transition(.opacity)
                .onDisappear { goToFileTargetPaneID = nil }
            }
        }
        .background(AppColors.canvasBackground)
        .foregroundStyle(AppColors.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: bootstrapShellIfNeeded)
        .onChange(of: workspace.activeTabID) { _, _ in
            noteIsReading = false
            noteSplitLayout = .none
            showNoteFindBar = false
        }
        .onChange(of: workspace.activeVaultID) { _, _ in
            splitRoot = nil
            auxiliaryPanes = [:]
            paneUIState = [:]
            focusedPaneID = EditorSplitTree.rootPaneID
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
        .background {
            Button("") { showGoToFile = true }
                .keyboardShortcut("o", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .vaultFolderPicker(purpose: $vaultFolderPickerPurpose) { url, purpose in
            vaultFolderPickerHandler?(url, purpose)
            vaultFolderPickerHandler = nil
        }
    }
    #endif

    // MARK: - Tab bar (Chrome-like + Obsidian mobile chrome)

    private var tabChromeControlSize: CGFloat {
        #if os(iOS)
        AppColors.minimumTouchTarget
        #else
        28
        #endif
    }

    private var tabPlusSlotWidth: CGFloat {
        #if os(iOS)
        AppColors.minimumTouchTarget
        #else
        34
        #endif
    }

    private let tabMaxWidth: CGFloat = 240
    private let tabMinWidth: CGFloat = 115
    private let singleTabWidth: CGFloat = 216

    private func paneTabBar<Leading: View>(
        tabs: [WorkspaceTab],
        activeTabID: String,
        onSelect: @escaping (WorkspaceTab) -> Void,
        onClose: @escaping (String) -> Void,
        onCloseAll: @escaping () -> Void,
        onAddTab: @escaping () -> Void,
        showsTrailingChrome: Bool,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 0) {
            leading()

            GeometryReader { geo in
                let trailingSlot: CGFloat = showsTrailingChrome ? sidebarToggleTrailingSlot : 28
                let plusSlot: CGFloat = tabPlusSlotWidth
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
                            .frame(width: tabChromeControlSize, height: tabChromeControlSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
                    .help("New tab")
                    .accessibilityLabel("New tab")

                    Spacer(minLength: 0)
                }
            }

            paneTabListMenu(
                tabs: tabs,
                activeTabID: activeTabID,
                onSelect: onSelect,
                onCloseAll: onCloseAll
            )

            if showsTrailingChrome {
                chromeIconButton(
                    "sidebar.right",
                    tip: rightSidebarVisible ? "Collapse right sidebar" : "Expand right sidebar",
                    isActive: rightSidebarVisible,
                    iconSize: sidebarToggleIconSize,
                    frameSize: sidebarToggleFrameSize
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
        .frame(height: tabBarRowHeight)
    }

    @ViewBuilder
    private func paneTabSeparator(
        before: WorkspaceTab,
        after: WorkspaceTab,
        activeTabID: String
    ) -> some View {
        if before.id != activeTabID && after.id != activeTabID {
            Rectangle()
                .fill(AppColors.borderSubtle)
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
                        .frame(width: tabChromeControlSize, height: tabChromeControlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textMuted)
                .accessibilityLabel("Close tab")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: tabBarRowHeight)
        .frame(maxHeight: .infinity, alignment: .center)
        .shellTabChrome(isActive: isActive)
        .contentShape(ShellTabShape())
        .onTapGesture(perform: onSelect)
    }

    private func paneTabListMenu(
        tabs: [WorkspaceTab],
        activeTabID: String,
        onSelect: @escaping (WorkspaceTab) -> Void,
        onCloseAll: @escaping () -> Void
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
            if !tabs.isEmpty {
                Divider()
                Button("Close all tabs", role: .destructive, action: onCloseAll)
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: tabChromeControlSize, height: tabChromeControlSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("List tabs")
        .accessibilityLabel("List tabs")
    }

    /// iPad Stage Manager: traffic-light band when windowed; Mac/fullscreen unchanged.
    @ViewBuilder
    private func iPadWindowedTabChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if os(iOS)
        if usesDesktopChrome && usesStageManagerTopBand {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: AppColors.iPadStageManagerTopBandHeight)
                content()
                    .frame(height: tabBarRowHeight)
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }

    #if os(iOS)
    private func scheduleIPadWindowLayoutUpdate(size: CGSize) {
        iPadLayoutDebounceTask?.cancel()
        iPadLayoutDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            applyIPadWindowLayout(size: size)
        }
    }

    /// Detect floating Stage Manager windows without thrashing layout on every frame change.
    private func applyIPadWindowLayout(size: CGSize) {
        let screen = UIScreen.main.bounds.size
        let enterThreshold: CGFloat = 28
        let exitThreshold: CGFloat = 10

        let looksFloating: Bool
        if usesStageManagerTopBand {
            looksFloating = size.width < screen.width - exitThreshold
                || size.height < screen.height - exitThreshold
        } else {
            looksFloating = size.width < screen.width - enterThreshold
                || size.height < screen.height - enterThreshold
        }

        guard usesStageManagerTopBand != looksFloating else { return }
        usesStageManagerTopBand = looksFloating
    }
    #endif

    /// Obsidian tab row: sidebar toggle on the left (below traffic lights on iPad).
    @ViewBuilder
    private func tabBarLeading(for paneID: String) -> some View {
        #if os(iOS)
        if usesDesktopChrome {
            chromeIconButton(
                "sidebar.left",
                tip: sidebarVisible ? "Hide sidebar" : "Show sidebar",
                isActive: sidebarVisible,
                iconSize: iPadSidebarToggleIconSize,
                frameSize: iPadSidebarToggleFrameSize
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarVisible.toggle()
                }
            }
            .frame(width: iPadSidebarToggleSlotWidth)
        }
        #elseif os(macOS)
        if !sidebarVisible && usesDesktopChrome {
            if macPaneTrafficLightClearance(for: paneID) > 0 {
                Color.clear
                    .frame(width: macPaneTrafficLightClearance(for: paneID))
            }
            chromeIconButton(
                "sidebar.left",
                tip: "Expand sidebar",
                iconSize: sidebarToggleIconSize,
                frameSize: sidebarToggleFrameSize
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarVisible = true
                }
            }
            .frame(width: sidebarToggleLeadingSlotWidth)
        }
        #endif
    }

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

    private var documentNavLeadingWidth: CGFloat {
        #if os(iOS)
        usesDesktopChrome ? 72 : 100
        #else
        72
        #endif
    }

    private var documentNavTrailingWidth: CGFloat {
        #if os(iOS)
        usesDesktopChrome ? 120 : 140
        #else
        120
        #endif
    }

    private func chromeIconButton(
        _ name: String,
        tip: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        iconSize: CGFloat? = nil,
        frameSize: CGFloat? = nil,
        action: @escaping () -> Void = {}
    ) -> some View {
        #if os(iOS)
        let resolvedIconSize = iconSize ?? 15
        let resolvedFrameSize = frameSize ?? AppColors.minimumTouchTarget
        #else
        let resolvedIconSize = iconSize ?? 13
        let resolvedFrameSize = frameSize ?? 22
        #endif
        return Button(action: action) {
            Image(systemName: name)
                .font(.system(size: resolvedIconSize, weight: .medium))
                .foregroundStyle(
                    isEnabled
                        ? (isActive ? AppColors.textPrimary : AppColors.textSecondary)
                        : AppColors.textMuted.opacity(0.35)
                )
                .frame(width: resolvedFrameSize, height: resolvedFrameSize)
                .background(
                    RoundedRectangle(cornerRadius: resolvedFrameSize > 30 ? 6 : 4)
                        .fill(isActive ? AppColors.sidebarSelection.opacity(0.85) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(tip)
        .accessibilityLabel(tip)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Placeholder pills

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
    let clearHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(0, clearHeight - 1))
            ShellHairline()
        }
        .allowsHitTesting(false)
    }
}

extension WorkspaceShellView {
    fileprivate var chromeRowHairline: some View {
        ChromeRowHairline(clearHeight: tabBarChromeHeight)
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

private struct ShellActiveTabOutline: Shape {
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
                        .shadow(color: Color.black.opacity(0.04), radius: 0.5, y: -0.5)
                }
            }
            .overlay {
                if isActive {
                    ShellActiveTabOutline()
                        .stroke(AppColors.border.opacity(0.65), lineWidth: 1)
                }
            }
            .clipShape(ShellTabShape())
    }
}

#if os(macOS)
import AppKit

/// Applies hidden title-bar chrome once per window. Must not touch `NSWindow` synchronously
/// from `viewDidMoveToWindow` — that re-enters SwiftUI preference resolution and overflows the stack.
private enum MacWindowChrome {
    private static let configured = NSHashTable<NSWindow>.weakObjects()

    static func configureOnce(_ window: NSWindow?) {
        guard let window, !configured.contains(window) else { return }
        configured.add(window)

        window.titleVisibility = .hidden
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.contentView?.clipsToBounds = false
    }
}

private struct MacWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        DispatchQueue.main.async {
            MacWindowChrome.configureOnce(window)
        }
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
