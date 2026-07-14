import Foundation
import Observation

struct SidebarFileRow: Identifiable, Equatable {
    let file: WorkspaceFileEntry
    let depth: Int
    let isLastInParent: Bool

    var id: String { file.id }
}

/// Per-vault UI state saved when switching away from a vault.
struct VaultWorkspaceSnapshot: Codable {
    var tabs: [WorkspaceTab]
    var activeTabID: String
    var selectedFileID: String?
    var expandedFolderIDs: Set<String>
    var bookmarkedFileIDs: Set<String> = []
    var bookmarks: [WorkspaceBookmark] = []
}

struct ExternalVaultSync {
    var scan: VaultFilesystem.ScanResult
    var canvasMetadataChanged: Bool
    var removedCanvasIDs: Set<String>
}

@Observable
final class WorkspaceStore {
    var tabs: [WorkspaceTab] = []
    var activeTabID = ""
    var files: [WorkspaceFileEntry] = []
    var selectedFileID: String?
    var expandedFolderIDs: Set<String> = []
    var bookmarks: [WorkspaceBookmark] = []
    /// When set, shows the add/edit bookmark sheet for this file.
    var bookmarkEditorFileID: String?
    /// When set, the sidebar shows an inline rename field on that file row.
    var inlineRenameFileID: String?
    var vaults: [WorkspaceVault] = []
    var activeVaultID: String?
    var isVaultManagerOpen = false
    var isHelpOpen = false
    var sortOrder: SidebarSortOrder = .nameAscending
    var vaultAlert: VaultAlert?
    /// Bumped when the cached wikilink graph changes — drives graph link refresh.
    private(set) var graphLinksVersion = 0

    /// Called when a canvas file is removed from the workspace.
    var onCanvasDocumentRemoved: ((String) -> Void)?
    /// Called when a canvas file path/id changes (folder rename/move).
    var onCanvasDocumentRekeyed: ((String, String) -> Void)?
    /// Called after a vault is loaded from disk with canvas snapshots.
    var onVaultCanvasLoaded: (([String: CanvasDocumentSnapshot]) -> Void)?
    /// Called after an external/incremental vault rescan completes.
    var onExternalVaultSynced: ((ExternalVaultSync) -> Void)?
    /// Flush the active vault's notes and canvases to disk before switching away.
    var onFlushActiveVaultToDisk: (() -> Void)?

    private var vaultSnapshots: [String: VaultWorkspaceSnapshot] = [:]
    private var graphLinkIndex = GraphLinkIndex()
    private var graphLinkRebuildTask: Task<Void, Never>?
    private var graphLinkCacheSaveTask: Task<Void, Never>?

    private struct SidebarRowDescriptor: Equatable {
        let fileID: String
        let depth: Int
        let isLastInParent: Bool
    }

    @ObservationIgnored private var cachedSidebarRowDescriptors: [SidebarRowDescriptor] = []
    @ObservationIgnored private var sidebarRowsFilesGeneration: UInt = 0
    @ObservationIgnored private var sidebarRowsCacheFilesGeneration: UInt = .max
    @ObservationIgnored private var sidebarRowsCacheExpandedFolders: Set<String> = []
    @ObservationIgnored private var sidebarRowsCacheSortOrder: SidebarSortOrder = .nameAscending

    @ObservationIgnored private var goToFileSearchIndex = GoToFileSearchIndex()
    @ObservationIgnored private var goToFileIndexGeneration: UInt = .max
    @ObservationIgnored private var filesystemWatchSuppressedUntil: Date?
    @ObservationIgnored private var vaultSyncTask: Task<Void, Never>?
    @ObservationIgnored private var scanIssuesReportedVaultIDs: Set<String> = []
    @ObservationIgnored private static let acknowledgedScanIssuesKey = "acknowledgedVaultScanIssues"
    private var navigationBackStack: [String] = []
    private var navigationForwardStack: [String] = []
    private var isApplyingNavigation = false

    var canNavigateBack: Bool { !navigationBackStack.isEmpty }
    var canNavigateForward: Bool { !navigationForwardStack.isEmpty }

    var graphEdges: [GraphEdge] { graphLinkIndex.edges }

    var graphEligibleFileCount: Int {
        files.filter { $0.kind == .note || $0.kind == .canvas }.count
    }

    func graphNeighborhood(around fileID: String, depth: Int) -> Set<String> {
        graphLinkIndex.neighborhood(around: fileID, depth: depth)
    }

    var activeVault: WorkspaceVault? {
        vaults.first { $0.id == activeVaultID } ?? vaults.first
    }

    var activeVaultURL: URL? {
        activeVault.map { VaultSecurityAccess.resolvedURL(for: $0) }
    }

    var vaultName: String {
        activeVault?.name ?? "Dreft"
    }

    var activeTab: WorkspaceTab? {
        tabs.first { $0.id == activeTabID } ?? tabs.first
    }

    // MARK: - Vault lifecycle

    func reportVaultError(title: String, message: String) {
        vaultAlert = VaultAlert(title: title, message: message)
    }

    func clearVaultAlert() {
        vaultAlert = nil
    }

    func bootstrapDefaultVaultIfNeeded() {
        guard vaults.isEmpty else { return }
        do {
            let vault = try VaultFilesystem.bootstrapDefaultVault()
            vaults = [vault]
            activeVaultID = vault.id
            loadVaultFromDisk(vault)
        } catch {
            reportVaultError(title: "Couldn't create default vault", message: error.localizedDescription)
        }
    }

    func createVault(name: String, parentDirectory: String, parentBookmark: Data? = nil) throws {
        if let parentBookmark {
            _ = VaultSecurityAccess.beginParentAccess(bookmark: parentBookmark)
        }

        let parentURL = URL(fileURLWithPath: parentDirectory, isDirectory: true).standardizedFileURL
        let vaultURL = parentURL.appendingPathComponent(name, isDirectory: true)
        var vault = try VaultFilesystem.createVault(at: vaultURL, name: name)
        VaultSecurityAccess.refreshBookmarkIfNeeded(for: &vault, url: vaultURL)
        VaultSecurityAccess.beginAccess(
            vaultID: vault.id,
            url: vaultURL,
            bookmark: vault.securityScopedBookmark
        )

        vaults.append(vault)
        switchVault(vault.id)
    }

    func openVault(at url: URL, bookmarkData: Data? = nil) {
        if let reason = VaultPathPolicy.unsuitableVaultMessage(for: url) {
            reportVaultError(title: "Can't open this folder as a vault", message: reason)
            return
        }

        let standardized = url.standardizedFileURL
        if let existing = vaults.first(where: {
            VaultSecurityAccess.resolvedURL(for: $0).standardizedFileURL == standardized
        }) {
            switchVault(existing.id)
            return
        }

        _ = standardized.startAccessingSecurityScopedResource()
        var vault = WorkspaceVault(name: standardized.lastPathComponent, path: standardized.path)
        vault.securityScopedBookmark = bookmarkData ?? VaultSecurityAccess.createBookmark(for: standardized)
        VaultSecurityAccess.refreshBookmarkIfNeeded(for: &vault, url: standardized)
        VaultSecurityAccess.beginAccess(
            vaultID: vault.id,
            url: standardized,
            bookmark: vault.securityScopedBookmark
        )

        vaults.append(vault)
        switchVault(vault.id)
    }

    func switchVault(_ id: String) {
        guard vaults.contains(where: { $0.id == id }) else { return }
        guard id != activeVault?.id else { return }

        onFlushActiveVaultToDisk?()

        if let currentID = activeVault?.id {
            vaultSnapshots[currentID] = currentWorkspaceSnapshot()
        }
        activeVaultID = id

        guard let vault = activeVault else { return }
        loadVaultFromDisk(vault)

        if let snapshot = vaultSnapshots[id] {
            restoreUIState(from: snapshot)
        }
    }

    func removeVault(_ id: String) {
        guard vaults.count > 1 else { return }
        let wasActive = activeVault?.id == id
        vaults.removeAll { $0.id == id }
        vaultSnapshots[id] = nil
        scanIssuesReportedVaultIDs.remove(id)
        if wasActive, let fallback = vaults.first?.id {
            switchVault(fallback)
        }
    }

    func loadVaultFromDisk(_ vault: WorkspaceVault) {
        let vaultURL = VaultSecurityAccess.resolvedURL(for: vault)
        if !FileManager.default.fileExists(atPath: vaultURL.path) {
            do {
                _ = try VaultFilesystem.createVault(at: vaultURL, name: vault.name)
            } catch {
                reportVaultError(title: "Couldn't open vault", message: error.localizedDescription)
                return
            }
        }
        var scan = VaultFilesystem.scan(vaultURL: vaultURL)
        if !scan.issues.isEmpty {
            reportScanIssues(scan.issues, vaultID: vault.id)
        }
        if scan.files.isEmpty {
            do {
                try VaultFilesystem.createNote(
                    relativePath: "Welcome.md",
                    vaultURL: vaultURL,
                    content: VaultFilesystem.welcomeNoteContent
                )
                scan = VaultFilesystem.scan(vaultURL: vaultURL)
            } catch {
                reportVaultError(title: "Couldn't create welcome note", message: error.localizedDescription)
            }
        }
        files = scan.files
        markSidebarRowsDirty()
        onVaultCanvasLoaded?(scan.canvasSnapshots)

        if tabs.isEmpty, let first = files.first(where: { $0.kind == .note || $0.kind == .canvas }) {
            openTab(for: first)
        } else if tabs.isEmpty {
            tabs = [WorkspaceTab(
                id: "t" + UUID().uuidString.prefix(8).lowercased(),
                title: "New tab",
                kind: .newTab,
                fileID: nil
            )]
            activeTabID = tabs[0].id
        }
        scheduleGraphLinkRebuild()
    }

    // MARK: - Persistence (app state only — file contents live on disk)

    func persistedState() -> PersistedAppState {
        PersistedAppState(
            vaults: vaults,
            activeVaultID: activeVault?.id,
            vaultSnapshots: vaultSnapshots,
            currentWorkspace: currentWorkspaceSnapshot(),
            sortOrder: sortOrder
        )
    }

    func restore(from state: PersistedAppState) {
        vaults = state.vaults
        activeVaultID = state.activeVaultID
        vaultSnapshots = state.vaultSnapshots
        sortOrder = state.sortOrder
        migrateLegacyVaultPaths()
        removeUnsuitableVaults()
        VaultSecurityAccess.restoreAccess(for: vaults)
        // The vault must be scanned before restoring UI state — tabs, bookmarks,
        // and the selection are validated against `files` and would otherwise be
        // silently dropped on every launch.
        if let vault = activeVault {
            loadVaultFromDisk(vault)
        }
        restoreUIState(from: state.currentWorkspace)
    }

    private static let vaultMigrationNoticeKey = "didShowVaultStorageMigrationNotice"

    /// The iOS app container UUID changes on every app update, so absolute vault
    /// paths saved by a previous version point at a container that no longer
    /// exists. Rewrite them onto the current container when the target exists.
    private static func rebasedContainerPath(_ path: String) -> String {
        #if os(iOS)
        let home = NSHomeDirectory()
        guard !path.hasPrefix(home + "/") else { return path }
        guard let range = path.range(of: "/Containers/Data/Application/") else { return path }
        let tail = path[range.upperBound...]
        guard let slash = tail.firstIndex(of: "/") else { return path }
        let relative = String(tail[tail.index(after: slash)...])
        let rebased = home + "/" + relative
        return FileManager.default.fileExists(atPath: rebased) ? rebased : path
        #else
        return path
        #endif
    }

    private func migrateLegacyVaultPaths() {
        let defaultURL = VaultFilesystem.defaultVaultURL()
        let defaultPath = VaultSecurityAccess.canonicalSandboxPath(defaultURL)
        var didRemapLegacyVault = false
        for index in vaults.indices {
            vaults[index].path = Self.rebasedContainerPath(vaults[index].path)
            let pathURL = URL(fileURLWithPath: vaults[index].path, isDirectory: true)
            let canonicalVaultPath = VaultSecurityAccess.canonicalSandboxPath(pathURL)

            // Already at the correct in-app vault location — skip.
            if canonicalVaultPath == defaultPath,
               FileManager.default.fileExists(atPath: pathURL.path) {
                continue
            }

            // External vault with a saved permission bookmark: never clobber it,
            // even if the bookmark is momentarily stale — access is re-requested later.
            if vaults[index].securityScopedBookmark != nil {
                continue
            }

            let isLegacyDesktop = vaults[index].path.hasSuffix("/Desktop") && !vaults[index].path.contains("/Dreft")
            let isLegacyUserDocuments = vaults[index].path.contains("/Documents/Dreft")
                && !VaultSecurityAccess.isInsideAppContainer(pathURL)
            let missingPath = !FileManager.default.fileExists(atPath: pathURL.path)
            let externalWithoutBookmark = !VaultSecurityAccess.isInsideAppContainer(pathURL)

            if isLegacyDesktop || isLegacyUserDocuments || missingPath || externalWithoutBookmark {
                // Only the legacy locations warrant the one-time migration notice.
                if isLegacyDesktop || isLegacyUserDocuments {
                    didRemapLegacyVault = true
                }
                vaults[index].path = defaultURL.path
                vaults[index].name = defaultURL.lastPathComponent
                vaults[index].securityScopedBookmark = nil
            }
        }
        if didRemapLegacyVault,
           !UserDefaults.standard.bool(forKey: Self.vaultMigrationNoticeKey) {
            UserDefaults.standard.set(true, forKey: Self.vaultMigrationNoticeKey)
            reportVaultError(
                title: "Vault moved to app storage",
                message: """
                Sandboxed Dreft stores built-in vaults inside the app container now. \
                If you had notes in ~/Documents/Dreft, use Manage vaults → Open folder to reconnect that folder.
                """
            )
        }
        if vaults.isEmpty {
            do {
                let vault = try VaultFilesystem.bootstrapDefaultVault()
                vaults = [vault]
                activeVaultID = vault.id
            } catch {
                reportVaultError(title: "Couldn't restore default vault", message: error.localizedDescription)
            }
        } else if !FileManager.default.fileExists(atPath: defaultURL.path) {
            do {
                _ = try VaultFilesystem.createVault(at: defaultURL, name: defaultURL.lastPathComponent)
            } catch {
                reportVaultError(title: "Couldn't restore vault folder", message: error.localizedDescription)
            }
        }
    }

    private func removeUnsuitableVaults() {
        let removed = vaults.filter { vault in
            let url = VaultSecurityAccess.resolvedURL(for: vault)
            return VaultPathPolicy.unsuitableVaultMessage(for: url) != nil
        }
        guard !removed.isEmpty else { return }

        let removedIDs = Set(removed.map(\.id))
        vaults.removeAll { removedIDs.contains($0.id) }
        for id in removedIDs {
            vaultSnapshots[id] = nil
            scanIssuesReportedVaultIDs.remove(id)
        }
        if let activeID = activeVaultID, removedIDs.contains(activeID) {
            activeVaultID = vaults.first?.id
        }

        let names = removed.map(\.name).joined(separator: ", ")
        reportVaultError(
            title: "Removed unsuitable vault",
            message: """
            “\(names)” is too broad to use as a vault and was removed from your list. Your files on disk are unchanged.

            Use a dedicated folder instead (for example Documents/valeria), or Create new vault.
            """
        )
    }

    func allKnownFileIDs() -> Set<String> {
        Set(files.map(\.id))
    }

    private func currentWorkspaceSnapshot() -> VaultWorkspaceSnapshot {
        VaultWorkspaceSnapshot(
            tabs: tabs,
            activeTabID: activeTabID,
            selectedFileID: selectedFileID,
            expandedFolderIDs: expandedFolderIDs,
            bookmarkedFileIDs: Set(bookmarks.map(\.fileID)),
            bookmarks: bookmarks
        )
    }

    private func restoreUIState(from snapshot: VaultWorkspaceSnapshot) {
        tabs = snapshot.tabs.filter { tab in
            tab.fileID == nil || files.contains(where: { $0.id == tab.fileID })
        }
        if tabs.isEmpty, let first = files.first(where: { $0.kind == .note || $0.kind == .canvas }) {
            openTab(for: first)
        } else if tabs.isEmpty {
            tabs = [WorkspaceTab(
                id: "t" + UUID().uuidString.prefix(8).lowercased(),
                title: "New tab",
                kind: .newTab,
                fileID: nil
            )]
        }
        activeTabID = tabs.contains(where: { $0.id == snapshot.activeTabID })
            ? snapshot.activeTabID
            : (tabs.first?.id ?? "")
        if let selected = snapshot.selectedFileID, files.contains(where: { $0.id == selected }) {
            selectedFileID = selected
        } else {
            selectedFileID = tabs.first(where: { $0.id == activeTabID })?.fileID
        }
        expandedFolderIDs = snapshot.expandedFolderIDs.filter { id in
            files.contains(where: { $0.id == id && $0.kind == .folder })
        }
        if !snapshot.bookmarks.isEmpty {
            bookmarks = snapshot.bookmarks.filter { bookmark in
                files.contains(where: { $0.id == bookmark.fileID })
            }
        } else {
            bookmarks = snapshot.bookmarkedFileIDs.compactMap { fileID in
                guard let file = files.first(where: { $0.id == fileID }) else { return nil }
                return WorkspaceBookmark(
                    fileID: fileID,
                    title: Self.defaultBookmarkTitle(for: file),
                    group: ""
                )
            }
        }
    }

    // MARK: - Document helpers

    func documentTitle(for tab: WorkspaceTab?) -> String {
        guard let tab else { return "Dreft" }
        switch tab.kind {
        case .canvas:
            if let fileID = tab.fileID,
               let file = files.first(where: { $0.id == fileID }) {
                if let folderName = parentFolderName(for: file) {
                    return "\(folderName) / \(file.name)"
                }
                return file.name
            }
            return tab.title
        case .note, .newTab:
            return tab.title
        case .graph:
            return "Graph view"
        }
    }

    func file(for tab: WorkspaceTab) -> WorkspaceFileEntry? {
        guard let fileID = tab.fileID else { return nil }
        return files.first(where: { $0.id == fileID })
    }

    func visibleSidebarRows() -> [SidebarFileRow] {
        rebuildSidebarRowsCacheIfNeeded()
        let fileMap = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var rows: [SidebarFileRow] = []
        rows.reserveCapacity(cachedSidebarRowDescriptors.count)
        for descriptor in cachedSidebarRowDescriptors {
            guard let file = fileMap[descriptor.fileID] else { continue }
            rows.append(
                SidebarFileRow(
                    file: file,
                    depth: descriptor.depth,
                    isLastInParent: descriptor.isLastInParent
                )
            )
        }
        return rows
    }

    func goToFileResults(matching query: String) -> [WorkspaceFileEntry] {
        rebuildGoToFileIndexIfNeeded()
        return goToFileSearchIndex.search(query, files: files)
    }

    func isFolderExpanded(_ id: String) -> Bool {
        expandedFolderIDs.contains(id)
    }

    func toggleFolderExpanded(_ id: String) {
        if expandedFolderIDs.contains(id) {
            expandedFolderIDs.remove(id)
        } else {
            expandedFolderIDs.insert(id)
        }
    }

    var folderIDs: [String] {
        files.filter { $0.kind == .folder }.map(\.id)
    }

    var areAllFoldersExpanded: Bool {
        let ids = folderIDs
        guard !ids.isEmpty else { return false }
        return ids.allSatisfy { expandedFolderIDs.contains($0) }
    }

    func expandAllFolders() {
        expandedFolderIDs = Set(folderIDs)
    }

    func collapseAllFolders() {
        expandedFolderIDs = []
    }

    func toggleExpandCollapseAllFolders() {
        if areAllFoldersExpanded {
            collapseAllFolders()
        } else {
            expandAllFolders()
        }
    }

    // MARK: - File CRUD

    func createNote(inFolder folderID: String? = nil, named requestedName: String? = nil, replacingTabID: String? = nil) {
        guard let vaultURL = activeVaultURL else {
            reportVaultError(title: "No vault available", message: VaultErrorMessages.noActiveVault)
            return
        }
        let name: String
        if let requestedName {
            let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
            name = trimmed.isEmpty ? nextUntitledName(prefix: "Untitled", kind: .note) : trimmed
        } else {
            name = nextUntitledName(prefix: "Untitled", kind: .note)
        }
        let relativePath = VaultFilesystem.uniqueRelativePath(
            baseName: name, kind: .note, parentRelativePath: folderID, vaultURL: vaultURL
        )
        do {
            try VaultFilesystem.createNote(relativePath: relativePath, vaultURL: vaultURL)
        } catch {
            reportVaultError(title: "Couldn't create note", message: error.localizedDescription)
            return
        }
        let entry = WorkspaceFileEntry(
            id: relativePath,
            name: name,
            kind: .note,
            parentFolderID: folderID,
            relativePath: relativePath
        )
        insertFile(entry, under: folderID)
        openFileFromQuickSwitcher(entry, replacingTabID: replacingTabID)
    }

    func createCanvas(inFolder folderID: String? = nil) {
        guard let vaultURL = activeVaultURL else {
            reportVaultError(title: "No vault available", message: VaultErrorMessages.noActiveVault)
            return
        }
        let name = nextUntitledName(prefix: "Untitled canvas", kind: .canvas)
        let relativePath = VaultFilesystem.uniqueRelativePath(
            baseName: name, kind: .canvas, parentRelativePath: folderID, vaultURL: vaultURL
        )
        do {
            try VaultFilesystem.createCanvas(relativePath: relativePath, vaultURL: vaultURL)
        } catch {
            reportVaultError(title: "Couldn't create canvas", message: error.localizedDescription)
            return
        }
        let entry = WorkspaceFileEntry(
            id: relativePath,
            name: name,
            kind: .canvas,
            parentFolderID: folderID,
            relativePath: relativePath
        )
        insertFile(entry, under: folderID)
        openTab(for: entry)
    }

    func createFolder(inFolder folderID: String? = nil) {
        guard let vaultURL = activeVaultURL else {
            reportVaultError(title: "No vault available", message: VaultErrorMessages.noActiveVault)
            return
        }
        let name = nextUntitledName(prefix: "Untitled folder", kind: .folder)
        let relativePath = VaultFilesystem.uniqueRelativePath(
            baseName: name, kind: .folder, parentRelativePath: folderID, vaultURL: vaultURL
        )
        do {
            try VaultFilesystem.createFolder(relativePath: relativePath, vaultURL: vaultURL)
        } catch {
            reportVaultError(title: "Couldn't create folder", message: error.localizedDescription)
            return
        }
        let entry = WorkspaceFileEntry(
            id: relativePath,
            name: name,
            kind: .folder,
            parentFolderID: folderID,
            relativePath: relativePath
        )
        insertFile(entry, under: folderID)
        expandedFolderIDs.insert(relativePath)
        selectedFileID = relativePath
    }

    func selectFile(_ id: String) {
        guard let file = files.first(where: { $0.id == id }) else { return }

        if !isApplyingNavigation,
           let current = selectedFileID,
           current != id {
            navigationBackStack.append(current)
            navigationForwardStack.removeAll()
        }

        selectedFileID = id
        switch file.kind {
        case .note, .canvas:
            openTab(for: file)
        case .folder:
            toggleFolderExpanded(id)
        case .image:
            break
        }
    }

    func goBack() {
        guard let previous = navigationBackStack.popLast(),
              let current = selectedFileID else { return }
        navigationForwardStack.append(current)
        isApplyingNavigation = true
        selectFile(previous)
        isApplyingNavigation = false
    }

    func goForward() {
        guard let next = navigationForwardStack.popLast(),
              let current = selectedFileID else { return }
        navigationBackStack.append(current)
        isApplyingNavigation = true
        selectFile(next)
        isApplyingNavigation = false
    }

    func backlinkCount(for fileID: String) -> Int {
        graphLinkIndex.incomingCount(for: fileID)
    }

    func incomingLinkIDs(for fileID: String) -> [String] {
        graphLinkIndex.incomingLinkIDs(for: fileID)
    }

    func outgoingLinkIDs(for fileID: String) -> [String] {
        graphLinkIndex.outgoingLinkIDs(for: fileID)
    }

    func revealInNavigation(_ fileID: String) {
        guard files.contains(where: { $0.id == fileID }) else { return }
        selectedFileID = fileID
        var parentID = files.first(where: { $0.id == fileID })?.parentFolderID
        while let id = parentID {
            expandedFolderIDs.insert(id)
            parentID = files.first(where: { $0.id == id })?.parentFolderID
        }
    }

    func beginInlineRename(for fileID: String) {
        inlineRenameFileID = fileID
        revealInNavigation(fileID)
    }

    func endInlineRename() {
        inlineRenameFileID = nil
    }

    func dreftURL(for fileID: String) -> String? {
        guard let vault = activeVault,
              let file = files.first(where: { $0.id == fileID }) else { return nil }
        return dreftURL(forRelativePath: file.relativePath, vaultName: vault.name)
    }

    func dreftURL(forRelativePath relativePath: String) -> String? {
        guard let vault = activeVault else { return nil }
        return dreftURL(forRelativePath: relativePath, vaultName: vault.name)
    }

    func fileID(forRelativePath relativePath: String) -> String? {
        files.first(where: { $0.relativePath == relativePath })?.id
    }

    private func dreftURL(forRelativePath relativePath: String, vaultName: String) -> String? {
        let encodedVault = vaultName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? vaultName
        let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
        return "dreft://open?vault=\(encodedVault)&file=\(encodedPath)"
    }

    func vaultRelativePath(for fileID: String) -> String? {
        files.first(where: { $0.id == fileID })?.relativePath
    }

    static func defaultBookmarkTitle(for file: WorkspaceFileEntry) -> String {
        (file.relativePath as NSString).lastPathComponent
    }

    func bookmark(for fileID: String) -> WorkspaceBookmark? {
        bookmarks.first(where: { $0.fileID == fileID })
    }

    func isBookmarked(_ fileID: String) -> Bool {
        bookmarks.contains(where: { $0.fileID == fileID })
    }

    var bookmarkGroups: [String] {
        Array(Set(bookmarks.map(\.group).filter { !$0.isEmpty })).sorted()
    }

    var bookmarkEntries: [WorkspaceBookmarkEntry] {
        bookmarks.compactMap { bookmark in
            guard let file = files.first(where: { $0.id == bookmark.fileID }) else { return nil }
            return WorkspaceBookmarkEntry(bookmark: bookmark, file: file)
        }
        .sorted { lhs, rhs in
            let leftGroup = lhs.bookmark.group
            let rightGroup = rhs.bookmark.group
            if leftGroup != rightGroup {
                if leftGroup.isEmpty { return false }
                if rightGroup.isEmpty { return true }
                return leftGroup.localizedCaseInsensitiveCompare(rightGroup) == .orderedAscending
            }
            return lhs.bookmark.title.localizedCaseInsensitiveCompare(rhs.bookmark.title) == .orderedAscending
        }
    }

    func presentBookmarkEditor(for fileID: String) {
        guard files.contains(where: { $0.id == fileID }) else { return }
        bookmarkEditorFileID = fileID
    }

    func dismissBookmarkEditor() {
        bookmarkEditorFileID = nil
    }

    func saveBookmark(fileID: String, title: String, group: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard files.contains(where: { $0.id == fileID }),
              !trimmedTitle.isEmpty else { return }

        if let index = bookmarks.firstIndex(where: { $0.fileID == fileID }) {
            bookmarks[index].title = trimmedTitle
            bookmarks[index].group = trimmedGroup
        } else {
            bookmarks.append(
                WorkspaceBookmark(fileID: fileID, title: trimmedTitle, group: trimmedGroup)
            )
        }
        dismissBookmarkEditor()
    }

    func removeBookmark(_ fileID: String) {
        bookmarks.removeAll { $0.fileID == fileID }
    }

    func openTabToRight(for file: WorkspaceFileEntry) {
        selectedFileID = file.id

        let insertIndex: Int
        if let activeIndex = tabs.firstIndex(where: { $0.id == activeTabID }) {
            insertIndex = activeIndex + 1
        } else {
            insertIndex = tabs.count
        }

        if let existingIndex = tabs.firstIndex(where: { $0.fileID == file.id }) {
            let tab = tabs.remove(at: existingIndex)
            let adjustedIndex = min(insertIndex, tabs.count)
            tabs.insert(tab, at: adjustedIndex)
            activeTabID = tab.id
            return
        }

        let tabKind: WorkspaceTabKind = switch file.kind {
        case .canvas: .canvas
        case .note: .note
        default: .note
        }
        let tab = WorkspaceTab(
            id: "t" + UUID().uuidString.prefix(8).lowercased(),
            title: file.name,
            kind: tabKind,
            fileID: file.id
        )
        tabs.insert(tab, at: min(insertIndex, tabs.count))
        activeTabID = tab.id
    }

    func reportNewWindowUnsupported() {
        reportVaultError(
            title: "New window",
            message: "Opening files in a separate window isn't supported yet. Use a new tab instead."
        )
    }

    private func rekeyBookmarkFileID(from oldFileID: String, to newFileID: String) {
        guard let index = bookmarks.firstIndex(where: { $0.fileID == oldFileID }) else { return }
        bookmarks[index].fileID = newFileID
    }

    func renameFile(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = files.firstIndex(where: { $0.id == id }),
              let vaultURL = activeVaultURL else { return }

        var file = files[index]
        let newRelativePath = VaultFilesystem.renamedRelativePath(file: file, newDisplayName: trimmed)
        guard newRelativePath != file.relativePath else {
            if files[index].name != trimmed {
                files[index].name = trimmed
            }
            syncTabTitle(fileID: id, title: trimmed)
            return
        }

        do {
            try VaultFilesystem.renameOnDisk(from: file.relativePath, to: newRelativePath, vaultURL: vaultURL)
        } catch {
            reportVaultError(title: "Couldn't rename \"\(file.name)\"", message: error.localizedDescription)
            return
        }

        let oldID = file.id
        file.name = trimmed
        file.relativePath = newRelativePath
        file.id = newRelativePath
        file.modifiedAt = Date()
        files[index] = file

        if file.kind == .folder {
            rekeyDescendants(of: oldID, to: newRelativePath)
        }

        rekeyTabs(from: oldID, to: newRelativePath, newTitle: trimmed)
        rekeyBookmarkFileID(from: oldID, to: newRelativePath)
        if selectedFileID == oldID { selectedFileID = newRelativePath }
        expandedFolderIDs.remove(oldID)
        if file.kind == .folder { expandedFolderIDs.insert(newRelativePath) }
        markSidebarRowsDirty()
        scheduleGraphLinkRebuild()
    }

    func duplicateFile(_ id: String) {
        guard let original = files.first(where: { $0.id == id }),
              let vaultURL = activeVaultURL else {
            reportVaultError(title: "No vault available", message: VaultErrorMessages.noActiveVault)
            return
        }
        let newName = duplicateName(for: original.name, kind: original.kind)
        let newRelativePath = VaultFilesystem.uniqueRelativePath(
            baseName: newName, kind: original.kind,
            parentRelativePath: original.parentFolderID, vaultURL: vaultURL
        )
        do {
            try VaultFilesystem.duplicate(relativePath: original.relativePath, newRelativePath: newRelativePath, vaultURL: vaultURL)
        } catch {
            reportVaultError(title: "Couldn't duplicate \"\(original.name)\"", message: error.localizedDescription)
            return
        }
        reloadFromDisk()
        if let copy = files.first(where: { $0.relativePath == newRelativePath }) {
            openTab(for: copy)
        }
    }

    func deleteFile(_ id: String) {
        guard let vaultURL = activeVaultURL else {
            reportVaultError(title: "No vault available", message: VaultErrorMessages.noActiveVault)
            return
        }
        var removed: Set<String> = [id]
        var changed = true
        while changed {
            changed = false
            for file in files where !removed.contains(file.id) {
                if let parent = file.parentFolderID, removed.contains(parent) {
                    removed.insert(file.id)
                    changed = true
                }
            }
        }

        var deleted = Set<String>()
        var failures: [(path: String, error: Error)] = []
        for fileID in removed {
            guard let file = files.first(where: { $0.id == fileID }) else { continue }
            do {
                try VaultFilesystem.delete(relativePath: file.relativePath, vaultURL: vaultURL)
                deleted.insert(fileID)
                if file.kind == .canvas { onCanvasDocumentRemoved?(fileID) }
            } catch {
                failures.append((file.relativePath, error))
            }
        }
        if !failures.isEmpty {
            reportWriteFailures(title: "Couldn't delete some files", failures: failures)
        }

        files.removeAll { deleted.contains($0.id) }
        expandedFolderIDs.subtract(deleted)
        bookmarks.removeAll { deleted.contains($0.fileID) }
        markSidebarRowsDirty()
        tabs.removeAll { tab in tab.fileID.map { deleted.contains($0) } ?? false }

        if tabs.isEmpty {
            tabs = [WorkspaceTab(
                id: "t" + UUID().uuidString.prefix(8).lowercased(),
                title: "New tab",
                kind: .newTab,
                fileID: nil
            )]
        }
        if !tabs.contains(where: { $0.id == activeTabID }) {
            activeTabID = tabs[0].id
        }
        if let selected = selectedFileID, removed.contains(selected) {
            selectedFileID = nil
        }
        for fileID in deleted {
            graphLinkIndex.removeFile(id: fileID)
        }
        graphLinksVersion += 1
        scheduleGraphLinkCacheSave()
    }

    func path(for fileID: String) -> String {
        guard let file = files.first(where: { $0.id == fileID }) else { return "" }
        var components = [file.name]
        var parentID = file.parentFolderID
        var visited = Set<String>([file.id])

        while let id = parentID {
            guard !visited.contains(id),
                  let folder = files.first(where: { $0.id == id }) else { break }
            visited.insert(id)
            components.append(folder.name)
            parentID = folder.parentFolderID
        }
        return components.reversed().joined(separator: "/")
    }

    func updateNoteContent(for fileID: String, content: String) {
        guard let index = files.firstIndex(where: { $0.id == fileID }) else { return }
        guard files[index].noteContent != content else { return }
        files[index].noteContent = content
        updateGraphLinksForNote(fileID)
    }

    /// Ensures in-memory note bodies are written before the graph reads wikilinks.
    func flushNotesForGraph() {
        guard let vaultURL = activeVaultURL else { return }
        let result = VaultFilesystem.writeNotes(files, vaultURL: vaultURL)
        if result.hasFailures {
            reportWriteFailures(title: "Couldn't save notes for graph", failures: result.failures)
        }
    }

    func diskPath(for fileID: String) -> String? {
        guard let file = files.first(where: { $0.id == fileID }),
              let vault = activeVault else { return nil }
        return (vault.path as NSString).appendingPathComponent(file.relativePath)
    }

    func availableMoveDestinations(for fileID: String) -> [WorkspaceFileEntry] {
        files.filter {
            $0.kind == .folder
                && $0.id != fileID
                && canMove(fileID: fileID, toFolder: $0.id)
        }
    }

    func moveFile(_ fileID: String, toFolder folderID: String?) {
        guard canMove(fileID: fileID, toFolder: folderID),
              let index = files.firstIndex(where: { $0.id == fileID }),
              let vaultURL = activeVaultURL else { return }

        var file = files.remove(at: index)
        let newRelativePath = VaultFilesystem.uniqueRelativePath(
            baseName: file.name, kind: file.kind,
            parentRelativePath: folderID, vaultURL: vaultURL
        )
        do {
            try VaultFilesystem.renameOnDisk(from: file.relativePath, to: newRelativePath, vaultURL: vaultURL)
        } catch {
            files.insert(file, at: min(index, files.count))
            reportVaultError(title: "Couldn't move \"\(file.name)\"", message: error.localizedDescription)
            return
        }

        let oldID = file.id
        file.parentFolderID = folderID
        file.relativePath = newRelativePath
        file.id = newRelativePath

        if file.kind == .folder {
            rekeyDescendants(of: oldID, to: newRelativePath)
        }
        rekeyTabs(from: oldID, to: newRelativePath, newTitle: file.name)
        rekeyBookmarkFileID(from: oldID, to: newRelativePath)

        let insertIndex = insertionIndex(for: file, under: folderID)
        files.insert(file, at: insertIndex)
        if let folderID { expandedFolderIDs.insert(folderID) }
        reloadFromDisk()
    }

    func canMove(fileID: String, toFolder folderID: String?) -> Bool {
        guard fileID != folderID,
              files.contains(where: { $0.id == fileID }) else { return false }

        if let folderID {
            guard let folder = files.first(where: { $0.id == folderID }),
                  folder.kind == .folder else { return false }

            if let moving = files.first(where: { $0.id == fileID }),
               moving.kind == .folder,
               isDescendant(fileID: folderID, of: fileID) {
                return false
            }
        }
        return true
    }

    func openGraphTab() {
        if let existing = tabs.first(where: { $0.kind == .graph }) {
            activeTabID = existing.id
            return
        }
        let tab = WorkspaceTab(id: "t-graph", title: "Graph view", kind: .graph, fileID: nil)
        tabs.append(tab)
        activeTabID = tab.id
    }

    func openTab(for file: WorkspaceFileEntry) {
        openFileFromQuickSwitcher(file, replacingTabID: nil)
    }

    /// Opens a vault file, optionally replacing the current placeholder tab (e.g. "New tab").
    func openFileFromQuickSwitcher(_ file: WorkspaceFileEntry, replacingTabID: String?) {
        selectedFileID = file.id

        if let existing = tabs.first(where: { $0.fileID == file.id }) {
            activeTabID = existing.id
            if let replacingTabID, replacingTabID != existing.id {
                closeTab(replacingTabID)
            }
            return
        }

        let tabKind: WorkspaceTabKind = switch file.kind {
        case .canvas: .canvas
        case .note: .note
        default: .note
        }
        let tab = WorkspaceTab(
            id: "t" + UUID().uuidString.prefix(8).lowercased(),
            title: file.name,
            kind: tabKind,
            fileID: file.id
        )

        if let replacingTabID, let index = tabs.firstIndex(where: { $0.id == replacingTabID }) {
            tabs[index] = tab
        } else {
            tabs.append(tab)
        }
        activeTabID = tab.id
    }

    func addTab() {
        let id = "t" + UUID().uuidString.prefix(8).lowercased()
        tabs.append(WorkspaceTab(id: id, title: "New tab", kind: .newTab, fileID: nil))
        activeTabID = id
    }

    func closeTab(_ id: String) {
        var next = tabs.filter { $0.id != id }
        if next.isEmpty {
            next = [WorkspaceTab(
                id: "t" + UUID().uuidString.prefix(8).lowercased(),
                title: "New tab",
                kind: .newTab,
                fileID: nil
            )]
        }
        tabs = next
        if activeTabID == id {
            activeTabID = next[0].id
            selectedFileID = next[0].fileID
        }
    }

    func syncTabTitle(fileID: String, title: String) {
        guard let tabIndex = tabs.firstIndex(where: { $0.fileID == fileID }) else { return }
        tabs[tabIndex].title = title
    }

    func reloadFromDisk() {
        guard let vault = activeVault else { return }
        let ui = currentWorkspaceSnapshot()
        loadVaultFromDisk(vault)
        restoreUIState(from: ui)
    }

    func suppressFilesystemWatch(for interval: TimeInterval = 1.75) {
        filesystemWatchSuppressedUntil = Date().addingTimeInterval(interval)
    }

    func syncVaultFromDiskIfChanged(existingCanvasSnapshots: [String: CanvasDocumentSnapshot]) {
        guard shouldProcessFilesystemWatchEvent(), activeVault != nil else { return }
        guard let vaultURL = activeVaultURL else { return }

        vaultSyncTask?.cancel()
        let ui = currentWorkspaceSnapshot()
        let existingByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.relativePath, $0) })
        let canvasIDsBefore = Set(files.filter { $0.kind == .canvas }.map(\.id))
        let canvasSignatureBefore = canvasFileSignature(files)

        vaultSyncTask = Task { @MainActor in
            let options = VaultFilesystem.ScanOptions(
                existingFilesByPath: existingByPath,
                existingCanvasSnapshots: existingCanvasSnapshots
            )
            let scan = await Task.detached(priority: .utility) {
                VaultFilesystem.scan(vaultURL: vaultURL, options: options)
            }.value
            guard !Task.isCancelled else { return }

            let canvasSignatureAfter = canvasFileSignature(scan.files)
            let canvasMetadataChanged = canvasSignatureBefore != canvasSignatureAfter

            if !scan.issues.isEmpty, let vaultID = activeVault?.id {
                reportScanIssues(scan.issues, vaultID: vaultID)
            }
            files = scan.files
            markSidebarRowsDirty()
            restoreUIState(from: ui)
            scheduleGraphLinkRebuild()

            let canvasIDsAfter = Set(scan.files.filter { $0.kind == .canvas }.map(\.id))
            onExternalVaultSynced?(
                ExternalVaultSync(
                    scan: scan,
                    canvasMetadataChanged: canvasMetadataChanged,
                    removedCanvasIDs: canvasIDsBefore.subtracting(canvasIDsAfter)
                )
            )
        }
    }

    private func shouldProcessFilesystemWatchEvent() -> Bool {
        guard let until = filesystemWatchSuppressedUntil else { return true }
        if Date() >= until {
            filesystemWatchSuppressedUntil = nil
            return true
        }
        return false
    }

    private func canvasFileSignature(_ entries: [WorkspaceFileEntry]) -> [String] {
        entries
            .filter { $0.kind == .canvas }
            .map { "\($0.relativePath):\($0.modifiedAt.timeIntervalSince1970)" }
            .sorted()
    }

    // MARK: - Private

    private func scheduleGraphLinkRebuild() {
        graphLinkRebuildTask?.cancel()
        let filesSnapshot = files
        let vaultURL = activeVaultURL
        graphLinkRebuildTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }

            let cached = vaultURL.flatMap { GraphLinkIndexPersistence.load(vaultURL: $0) }

            if filesSnapshot.count >= 250 {
                let result = await Task.detached(priority: .userInitiated) {
                    let index = GraphLinkIndex()
                    let snapshot = index.sync(from: filesSnapshot, vaultURL: vaultURL, cache: cached)
                    return (index, snapshot)
                }.value
                graphLinkIndex = result.0
                if let vaultURL {
                    GraphLinkIndexPersistence.save(result.1, vaultURL: vaultURL)
                }
            } else {
                let snapshot = graphLinkIndex.sync(from: filesSnapshot, vaultURL: vaultURL, cache: cached)
                if let vaultURL {
                    GraphLinkIndexPersistence.save(snapshot, vaultURL: vaultURL)
                }
            }
            graphLinksVersion += 1
        }
    }

    private func scheduleGraphLinkCacheSave() {
        graphLinkCacheSaveTask?.cancel()
        guard let vaultURL = activeVaultURL else { return }
        let snapshot = graphLinkIndex.cacheSnapshot()
        graphLinkCacheSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            GraphLinkIndexPersistence.save(snapshot, vaultURL: vaultURL)
        }
    }

    private func updateGraphLinksForNote(_ fileID: String) {
        guard let file = files.first(where: { $0.id == fileID }), file.kind == .note else { return }
        graphLinkIndex.updateNoteContent(id: fileID, content: file.noteContent, modifiedAt: file.modifiedAt)
        graphLinksVersion += 1
        scheduleGraphLinkCacheSave()
    }

    private func rekeyDescendants(of oldFolderID: String, to newFolderID: String) {
        for index in files.indices {
            let oldPath = files[index].relativePath
            guard oldPath == oldFolderID || oldPath.hasPrefix(oldFolderID + "/") else { continue }

            let suffix = String(oldPath.dropFirst(oldFolderID.count))
            let newPath = newFolderID + suffix
            let oldFileID = files[index].id

            files[index].relativePath = newPath
            files[index].id = newPath
            if let parentID = files[index].parentFolderID {
                if parentID == oldFolderID {
                    files[index].parentFolderID = newFolderID
                } else if parentID.hasPrefix(oldFolderID + "/") {
                    let parentSuffix = String(parentID.dropFirst(oldFolderID.count))
                    files[index].parentFolderID = newFolderID + parentSuffix
                }
            }

            rekeyTabs(from: oldFileID, to: newPath, newTitle: files[index].name)
            if files[index].kind == .canvas {
                onCanvasDocumentRekeyed?(oldFileID, newPath)
            }
            if selectedFileID == oldFileID {
                selectedFileID = newPath
            }
            if bookmarks.contains(where: { $0.fileID == oldFileID }) {
                rekeyBookmarkFileID(from: oldFileID, to: newPath)
            }
        }

        let expandedKeys = expandedFolderIDs.filter { $0 == oldFolderID || $0.hasPrefix(oldFolderID + "/") }
        for key in expandedKeys {
            expandedFolderIDs.remove(key)
            if key == oldFolderID {
                expandedFolderIDs.insert(newFolderID)
            } else {
                let suffix = String(key.dropFirst(oldFolderID.count))
                expandedFolderIDs.insert(newFolderID + suffix)
            }
        }
    }

    private func rekeyTabs(from oldFileID: String, to newFileID: String, newTitle: String) {
        for index in tabs.indices where tabs[index].fileID == oldFileID {
            tabs[index].fileID = newFileID
            tabs[index].title = newTitle
        }
    }

    private func reportScanIssues(_ issues: [VaultScanIssue], vaultID: String) {
        let unacknowledged = issues.filter { !isScanIssueAcknowledged($0, vaultID: vaultID) }
        guard !unacknowledged.isEmpty else { return }
        guard !scanIssuesReportedVaultIDs.contains(vaultID) else { return }
        scanIssuesReportedVaultIDs.insert(vaultID)
        acknowledgeScanIssues(unacknowledged, vaultID: vaultID)
        reportVaultError(
            title: "Some vault files couldn't be read",
            message: unacknowledged.prefix(4).map { "\($0.path): \($0.message)" }.joined(separator: "\n")
                + (unacknowledged.count > 4 ? "\n…and \(unacknowledged.count - 4) more." : "")
        )
    }

    private func scanIssueKey(_ issue: VaultScanIssue, vaultID: String) -> String {
        "\(vaultID)|\(issue.path)|\(issue.message)"
    }

    private func isScanIssueAcknowledged(_ issue: VaultScanIssue, vaultID: String) -> Bool {
        acknowledgedScanIssueKeys().contains(scanIssueKey(issue, vaultID: vaultID))
    }

    private func acknowledgeScanIssues(_ issues: [VaultScanIssue], vaultID: String) {
        var keys = acknowledgedScanIssueKeys()
        for issue in issues {
            keys.insert(scanIssueKey(issue, vaultID: vaultID))
        }
        UserDefaults.standard.set(Array(keys), forKey: Self.acknowledgedScanIssuesKey)
    }

    private func acknowledgedScanIssueKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.acknowledgedScanIssuesKey) ?? [])
    }

    private func reportWriteFailures(title: String, failures: [(path: String, error: Error)]) {
        guard !failures.isEmpty else { return }
        reportVaultError(title: title, message: VaultBatchWriteResult(failures: failures).summaryMessage)
    }

    private func appendRowDescriptors(
        parentID: String?,
        depth: Int,
        into descriptors: inout [SidebarRowDescriptor],
        childrenIndex: [String?: [WorkspaceFileEntry]]
    ) {
        let siblings = childrenIndex[parentID] ?? []
        for (index, file) in siblings.enumerated() {
            let isLast = index == siblings.count - 1
            descriptors.append(
                SidebarRowDescriptor(fileID: file.id, depth: depth, isLastInParent: isLast)
            )
            if file.kind == .folder, isFolderExpanded(file.id) {
                appendRowDescriptors(
                    parentID: file.id,
                    depth: depth + 1,
                    into: &descriptors,
                    childrenIndex: childrenIndex
                )
            }
        }
    }

    private func rebuildSidebarRowsCacheIfNeeded() {
        if sidebarRowsCacheFilesGeneration == sidebarRowsFilesGeneration,
           sidebarRowsCacheExpandedFolders == expandedFolderIDs,
           sidebarRowsCacheSortOrder == sortOrder,
           !cachedSidebarRowDescriptors.isEmpty {
            return
        }

        let childrenIndex = buildChildrenIndex()
        var descriptors: [SidebarRowDescriptor] = []
        descriptors.reserveCapacity(max(files.count / 2, 16))
        appendRowDescriptors(parentID: nil, depth: 0, into: &descriptors, childrenIndex: childrenIndex)
        cachedSidebarRowDescriptors = descriptors
        sidebarRowsCacheFilesGeneration = sidebarRowsFilesGeneration
        sidebarRowsCacheExpandedFolders = expandedFolderIDs
        sidebarRowsCacheSortOrder = sortOrder
    }

    private func buildChildrenIndex() -> [String?: [WorkspaceFileEntry]] {
        var index: [String?: [WorkspaceFileEntry]] = [:]
        index.reserveCapacity(max(files.count / 8, 4))
        for file in files {
            index[file.parentFolderID, default: []].append(file)
        }
        for key in index.keys {
            index[key] = sortedSiblingFiles(index[key] ?? [])
        }
        return index
    }

    private func sortedSiblingFiles(_ siblings: [WorkspaceFileEntry]) -> [WorkspaceFileEntry] {
        siblings.sorted { lhs, rhs in
            let lhsIsFolder = lhs.kind == .folder
            let rhsIsFolder = rhs.kind == .folder
            if lhsIsFolder != rhsIsFolder { return lhsIsFolder }
            switch sortOrder {
            case .nameAscending:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .nameDescending:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            case .modifiedNewToOld: return lhs.modifiedAt > rhs.modifiedAt
            case .modifiedOldToNew: return lhs.modifiedAt < rhs.modifiedAt
            case .createdNewToOld: return lhs.createdAt > rhs.createdAt
            case .createdOldToNew: return lhs.createdAt < rhs.createdAt
            }
        }
    }

    private func markSidebarRowsDirty() {
        sidebarRowsFilesGeneration &+= 1
    }

    private func rebuildGoToFileIndexIfNeeded() {
        guard goToFileIndexGeneration != sidebarRowsFilesGeneration else { return }
        goToFileSearchIndex.rebuild(from: files)
        goToFileIndexGeneration = sidebarRowsFilesGeneration
    }

    private func insertFile(_ entry: WorkspaceFileEntry, under folderID: String?) {
        let insertIndex = insertionIndex(for: entry, under: folderID)
        files.insert(entry, at: insertIndex)
        if let folderID { expandedFolderIDs.insert(folderID) }
        markSidebarRowsDirty()
        scheduleGraphLinkRebuild()
    }

    private func insertionIndex(for file: WorkspaceFileEntry, under folderID: String?) -> Int {
        if let folderID, let folderIndex = files.firstIndex(where: { $0.id == folderID }) {
            return endOfSubtreeIndex(after: folderIndex)
        }
        if let lastRootIndex = files.lastIndex(where: { $0.parentFolderID == nil }) {
            return endOfSubtreeIndex(after: lastRootIndex)
        }
        return files.count
    }

    private func endOfSubtreeIndex(after index: Int) -> Int {
        guard index < files.count else { return files.count }
        let rootID = files[index].id
        var end = index + 1
        while end < files.count, isDescendant(fileID: files[end].id, of: rootID) {
            end += 1
        }
        return end
    }

    private func isDescendant(fileID: String, of ancestorID: String) -> Bool {
        var current = files.first(where: { $0.id == fileID })?.parentFolderID
        while let parent = current {
            if parent == ancestorID { return true }
            current = files.first(where: { $0.id == parent })?.parentFolderID
        }
        return false
    }

    private func parentFolderName(for file: WorkspaceFileEntry) -> String? {
        guard let parentID = file.parentFolderID,
              let parent = files.first(where: { $0.id == parentID }) else { return nil }
        return parent.name
    }

    private func nextUntitledName(prefix: String, kind: WorkspaceFileKind) -> String {
        let names = Set(files.filter { $0.kind == kind }.map(\.name))
        if prefix == "Untitled" {
            if !names.contains("Untitled") { return "Untitled" }
            var index = 1
            while names.contains("Untitled \(index)") { index += 1 }
            return "Untitled \(index)"
        }
        if !names.contains(prefix) { return prefix }
        var index = 1
        while names.contains("\(prefix) \(index)") { index += 1 }
        return "\(prefix) \(index)"
    }

    private func duplicateName(for name: String, kind: WorkspaceFileKind) -> String {
        let names = Set(files.filter { $0.kind == kind }.map(\.name))
        var index = 1
        while names.contains("\(name) \(index)") { index += 1 }
        return "\(name) \(index)"
    }
}
