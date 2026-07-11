import SwiftUI

enum SidebarLayout {
    static let defaultWidth: CGFloat = 248
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
    @State private var iconRailVisible = true
    @State private var sidebarPanel: SidebarPanel = .files
    @State private var showGoToFile = false
    @State private var noteIsReading = false
    @State private var noteSplitLayout: NoteSplitLayout = .none
    @State private var showNoteFindBar = false
    @AppStorage("sidebarWidth") private var sidebarWidthStorage = SidebarLayout.defaultWidth
    @State private var sidebarWidth = SidebarLayout.defaultWidth
    @State private var isResizingSidebar = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let workspace = WorkspaceStore()
        let registry = CanvasDocumentRegistry()

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

        workspace.onVaultCanvasLoaded = { snapshots in
            registry.setVaultURL(workspace.activeVaultURL)
            registry.load(from: snapshots)
            if let vaultURL = workspace.activeVaultURL {
                registry.migrateEmbeddedImages(vaultURL: vaultURL)
            }
        }
        if let vault = workspace.activeVault {
            workspace.loadVaultFromDisk(vault)
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
    #endif

    private var usesDesktopChrome: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
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
            if iconRailVisible && usesDesktopChrome {
                IconRailView(
                    workspace: workspace,
                    sidebarVisible: $sidebarVisible,
                    onGoToFile: { showGoToFile = true },
                    contentTopInset: iconRailTopInset
                )
                .frame(maxHeight: .infinity)
                ShellVerticalHairline()
            }

            if sidebarVisible && usesDesktopChrome {
                sidebarColumn
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            editorColumn
        }
        .animation(isResizingSidebar ? nil : .easeInOut(duration: 0.2), value: sidebarVisible)
    }

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            SidebarPanelSwitcherBar(sidebarVisible: $sidebarVisible, activePanel: $sidebarPanel)
                .frame(height: AppColors.chromeRowHeight)
                .background(AppColors.tabBarBackground)
                .overlay(alignment: .bottom) { ShellHairline() }

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

    private var editorColumn: some View {
        VStack(spacing: 0) {
            tabBar
                .frame(height: AppColors.chromeRowHeight)
                .background(AppColors.tabBarBackground)
                .overlay(alignment: .bottom) { ShellHairline() }
                #if os(macOS)
                .background { MacWindowDragHandle() }
                #endif

            documentNavBar
            canvasArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.canvasBackground)
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
                    replacingTabID: activeTab?.kind == .newTab ? activeTab?.id : nil
                )
                .zIndex(20)
                .transition(.opacity)
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
                    replacingTabID: activeTab?.kind == .newTab ? activeTab?.id : nil
                )
                .zIndex(20)
                .transition(.opacity)
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
        .onChange(of: workspace.selectedFileID) { _, _ in
            if workspace.activeTab?.kind == .note {
                noteIsReading = false
                noteSplitLayout = .none
                showNoteFindBar = false
            }
        }
        .animation(.easeOut(duration: 0.15), value: workspace.isVaultManagerOpen)
        .animation(.easeOut(duration: 0.15), value: workspace.isHelpOpen)
        .animation(.easeOut(duration: 0.15), value: workspace.bookmarkEditorFileID != nil)
        .animation(.easeOut(duration: 0.12), value: showGoToFile)
    }
    #endif

    // MARK: - Tab bar (Chrome-like + Obsidian mobile chrome)

    private let tabMaxWidth: CGFloat = 200
    private let tabMinWidth: CGFloat = 96
    private let singleTabWidth: CGFloat = 180

    private func chromeTabWidth(available: CGFloat) -> CGFloat {
        guard workspace.tabs.count > 1 else { return singleTabWidth }
        let share = available / CGFloat(workspace.tabs.count)
        return min(tabMaxWidth, max(tabMinWidth, share))
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            GeometryReader { geo in
                let plusSlot: CGFloat = 34
                let trailingSlot: CGFloat = 72
                let width = chromeTabWidth(available: max(0, geo.size.width - plusSlot - trailingSlot))
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(workspace.tabs) { tab in
                                tabButton(tab)
                                    .frame(width: width)
                            }
                        }
                    }
                    .padding(.leading, 8)

                    Button(action: workspace.addTab) {
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

            tabBarTrailing
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: AppColors.chromeRowHeight)
    }

    private var tabBarTrailing: some View {
        #if os(iOS)
        HStack(spacing: 10) {
            chromeIconButton(
                "point.3.connected.trianglepath.dotted",
                tip: "Graph view",
                isActive: workspace.activeTab?.kind == .graph
            ) {
                workspace.openGraphTab()
            }
        }
        .padding(.leading, 8)
        #else
        EmptyView()
        #endif
    }

    private func tabButton(_ tab: WorkspaceTab) -> some View {
        let isActive = tab.id == workspace.activeTabID
        return HStack(spacing: 8) {
            tabIcon(for: tab.kind)
            Text(tab.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isActive {
                Button {
                    workspace.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: AppColors.chromeRowHeight - 1)
        .shellTabChrome(isActive: isActive)
        .contentShape(ShellTabShape())
        .onTapGesture {
            workspace.activeTabID = tab.id
            workspace.selectedFileID = tab.fileID
        }
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
                #if os(iOS)
                chromeIconButton(
                    "point.3.connected.trianglepath.dotted",
                    tip: "Graph view",
                    isActive: workspace.activeTab?.kind == .graph
                ) {
                    workspace.openGraphTab()
                }
                #endif
                if activeTab?.kind == .note, let fileID = activeTab?.fileID {
                    ObsidianViewModeButton(isReading: $noteIsReading) {
                        noteSplitLayout = .none
                    }
                    NoteDocumentOptionsMenu(
                        workspace: workspace,
                        fileID: fileID,
                        isReading: $noteIsReading,
                        splitLayout: $noteSplitLayout,
                        sidebarVisible: $sidebarVisible,
                        sidebarPanel: $sidebarPanel,
                        showFindBar: $showNoteFindBar
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
                InfiniteCanvasView(
                    store: canvasStore,
                    workspace: workspace,
                    sidebarVisible: $sidebarVisible,
                    sidebarPanel: $sidebarPanel,
                    documentTitle: documentTitle,
                    vaultURL: workspace.activeVaultURL
                )
                .id(documentID)
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
        let radius: CGFloat = 8
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
            .background(isActive ? AppColors.canvasBackground : Color.clear)
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
        window.titlebarAppearsTransparent = true
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
