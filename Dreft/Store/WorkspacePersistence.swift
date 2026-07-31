import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

struct PersistedAppState: Codable {
    var vaults: [WorkspaceVault]
    var activeVaultID: String?
    var vaultSnapshots: [String: VaultWorkspaceSnapshot]
    var currentWorkspace: VaultWorkspaceSnapshot
    var sortOrder: SidebarSortOrder
}

struct WorkspacePersistenceLoadResult {
    var state: PersistedAppState?
    var restoredFromBackup: Bool
}

enum WorkspacePersistence {
    static var fileURL: URL {
        dreftDirectory(in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("workspace.json")
    }

    static var backupFileURL: URL {
        fileURL.appendingPathExtension("bak")
    }

    static func dreftDirectory(in container: URL) -> URL {
        container.appendingPathComponent("Dreft", isDirectory: true)
    }

    static func workspaceFileURL(in dreftDirectory: URL) -> URL {
        dreftDirectory.appendingPathComponent("workspace.json")
    }

    static func backupFileURL(in dreftDirectory: URL) -> URL {
        workspaceFileURL(in: dreftDirectory).appendingPathExtension("bak")
    }

    static func load() -> WorkspacePersistenceLoadResult {
        load(from: fileURL.deletingLastPathComponent())
    }

    static func load(from dreftDirectory: URL) -> WorkspacePersistenceLoadResult {
        if let state = decodeState(from: workspaceFileURL(in: dreftDirectory)) {
            return WorkspacePersistenceLoadResult(state: state, restoredFromBackup: false)
        }
        if let state = decodeState(from: backupFileURL(in: dreftDirectory)) {
            return WorkspacePersistenceLoadResult(state: state, restoredFromBackup: true)
        }
        return WorkspacePersistenceLoadResult(state: nil, restoredFromBackup: false)
    }

    static func save(_ state: PersistedAppState) throws {
        try save(state, to: fileURL.deletingLastPathComponent())
    }

    static func save(_ state: PersistedAppState, to dreftDirectory: URL) throws {
        try FileManager.default.createDirectory(at: dreftDirectory, withIntermediateDirectories: true)
        let workspaceURL = workspaceFileURL(in: dreftDirectory)
        let backupURL = backupFileURL(in: dreftDirectory)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: workspaceURL.path),
           decodeState(from: workspaceURL) != nil {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: workspaceURL, to: backupURL)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: workspaceURL, options: .atomic)
    }

    private static func decodeState(from url: URL) -> PersistedAppState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let state = try? decoder.decode(PersistedAppState.self, from: data) {
            return state
        }
        if let legacy = try? decoder.decode(LegacyPersistedAppState.self, from: data) {
            return legacy.asModernState()
        }
        return nil
    }
}

private struct LegacyPersistedAppState: Codable {
    var vaults: [WorkspaceVault]
    var activeVaultID: String?
    var vaultSnapshots: [String: LegacyVaultSnapshot]
    var currentWorkspace: LegacyVaultSnapshot
    var sortOrder: SidebarSortOrder

    struct LegacyVaultSnapshot: Codable {
        var tabs: [WorkspaceTab]
        var activeTabID: String
        var files: [WorkspaceFileEntry]?
        var selectedFileID: String?
        var expandedFolderIDs: Set<String>
    }

    func asModernState() -> PersistedAppState {
        func ui(_ legacy: LegacyVaultSnapshot) -> VaultWorkspaceSnapshot {
            VaultWorkspaceSnapshot(
                tabs: legacy.tabs,
                activeTabID: legacy.activeTabID,
                selectedFileID: legacy.selectedFileID,
                expandedFolderIDs: legacy.expandedFolderIDs
            )
        }
        var snapshots: [String: VaultWorkspaceSnapshot] = [:]
        for (key, value) in vaultSnapshots {
            snapshots[key] = ui(value)
        }
        return PersistedAppState(
            vaults: vaults,
            activeVaultID: activeVaultID,
            vaultSnapshots: snapshots,
            currentWorkspace: ui(currentWorkspace),
            sortOrder: sortOrder
        )
    }
}

@MainActor
final class WorkspacePersistenceCoordinator {
    private let workspace: WorkspaceStore
    private let documents: CanvasDocumentRegistry
    private var trackedVaultID: String?
    private var saveTask: Task<Void, Never>?
    private var scheduledSaveUrgency: CanvasSaveUrgency = .debounced
    private var terminationObserver: NSObjectProtocol?
    private let vaultWatcher = VaultFilesystemWatcher()
    private var dirtyTracker = VaultDirtyTracker()

    init(workspace: WorkspaceStore, documents: CanvasDocumentRegistry) {
        self.workspace = workspace
        self.documents = documents
        self.trackedVaultID = workspace.activeVault?.id
    }

    func start() {
        workspace.onFlushActiveVaultToDisk = { [weak self] in
            self?.markEntireActiveVaultDirty()
            self?.flushVaultContentsToDisk(for: self?.workspace.activeVault?.id)
        }
        workspace.onVaultCanvasLoaded = { [weak self] snapshots in
            guard let self else { return }
            self.documents.setVaultURL(self.workspace.activeVaultURL)
            self.documents.load(from: snapshots)
            if let vaultURL = self.workspace.activeVaultURL {
                self.documents.migrateEmbeddedImages(vaultURL: vaultURL)
            }
        }
        workspace.onExternalVaultSynced = { [weak self] sync in
            self?.applyExternalVaultSync(sync)
        }
        workspace.onNoteContentDirty = { [weak self] relativePath in
            self?.dirtyTracker.markNote(relativePath)
            self?.scheduleSave()
        }
        workspace.onFlushNoteToDisk = { [weak self] relativePath in
            self?.flushNoteToDisk(relativePath: relativePath)
        }
        workspace.onFlushCanvasToDisk = { [weak self] relativePath in
            self?.flushCanvasToDisk(relativePath: relativePath)
        }
        workspace.onFileRelativePathChanged = { [weak self] oldPath, newPath in
            self?.dirtyTracker.rekeyNote(from: oldPath, to: newPath)
            self?.dirtyTracker.rekeyCanvas(from: oldPath, to: newPath)
            self?.documents.rekeyVaultReferences(from: oldPath, to: newPath)
        }
        workspace.onWorkspaceStateDirty = { [weak self] in
            self?.dirtyTracker.markWorkspaceState()
            self?.scheduleSave()
        }
        documents.onCanvasMutated = { [weak self] urgency in
            self?.scheduleSave(urgency: urgency)
        }
        documents.onCanvasDirty = { [weak self] relativePath in
            self?.dirtyTracker.markCanvas(relativePath)
        }
        documents.onCanvasPersistError = { [weak self] title, message in
            self?.workspace.reportVaultError(title: title, message: message)
        }
        documents.onLinkedNoteBodyChanged = { [weak self] relativePath, body in
            self?.workspace.updateNoteContent(forRelativePath: relativePath, content: body)
        }

        observeWorkspaceUI()
        restartVaultWatcher()
        #if os(macOS)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                self.markEntireActiveVaultDirty()
                self.flushToDisk()
            }
        }
        #endif
    }

    private func observeWorkspaceUI() {
        withObservationTracking {
            _ = self.workspace.activeVault?.id
            _ = self.workspace.tabs
            _ = self.workspace.activeTabID
            _ = self.workspace.selectedFileID
            _ = self.workspace.expandedFolderIDs
            _ = self.workspace.sortOrder
            _ = self.workspace.bookmarks
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let vaultChanged = self.trackedVaultID != self.workspace.activeVault?.id
                self.documents.setVaultURL(self.workspace.activeVaultURL)
                self.trackedVaultID = self.workspace.activeVault?.id
                if vaultChanged {
                    self.restartVaultWatcher()
                }
                self.dirtyTracker.markWorkspaceState()
                self.scheduleSave()
                self.observeWorkspaceUI()
            }
        }
    }

    func refreshVaultFromDiskIfNeeded() {
        syncVaultFromDisk()
    }

    func flushPendingChanges() {
        markEntireActiveVaultDirty()
        workspace.markSaveStatus(.saving)
        flushToDisk()
        workspace.markSaveStatus(.saved)
    }

    private func restartVaultWatcher() {
        vaultWatcher.stop()
        guard let vaultURL = workspace.activeVaultURL else { return }
        vaultWatcher.start(watching: vaultURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncVaultFromDisk()
            }
        }
    }

    private func syncVaultFromDisk() {
        let snapshots = documents.snapshotAll(validIDs: workspace.allKnownFileIDs())
        workspace.syncVaultFromDiskIfChanged(existingCanvasSnapshots: snapshots)
    }

    private func applyExternalVaultSync(_ sync: ExternalVaultSync) {
        documents.setVaultURL(workspace.activeVaultURL)
        for id in sync.removedCanvasIDs {
            documents.remove(documentID: id)
        }
        if sync.canvasMetadataChanged {
            let validCanvasIDs = Set(workspace.files.filter { $0.kind == .canvas }.map(\.id))
            documents.applyCanvasSnapshots(sync.scan.canvasSnapshots, validCanvasIDs: validCanvasIDs)
        }
        documents.syncVaultFiles(workspace.files)
    }

    private func flushToDisk() {
        saveTask?.cancel()
        flushVaultContentsToDisk(for: workspace.activeVault?.id)
        if dirtyTracker.consumeWorkspaceState() {
            do {
                try WorkspacePersistence.save(workspace.persistedState())
            } catch {
                workspace.reportVaultError(
                    title: "Couldn't save workspace",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func flushVaultContentsToDisk(for vaultID: String?) {
        guard let vaultID,
              let vault = workspace.vaults.first(where: { $0.id == vaultID }) else { return }

        let dirtyNotes = dirtyTracker.consumeNotes()
        let dirtyCanvases = dirtyTracker.consumeCanvases()
        guard !dirtyNotes.isEmpty || !dirtyCanvases.isEmpty else { return }

        workspace.suppressFilesystemWatch()
        let vaultURL = VaultSecurityAccess.resolvedURL(for: vault)
        documents.setVaultURL(vaultURL)
        documents.migrateEmbeddedImages(vaultURL: vaultURL)

        if !dirtyNotes.isEmpty {
            let noteResult = writeDirtyNotes(dirtyNotes, vaultURL: vaultURL)
            let writtenNotes = noteResult.writtenPaths
            let unmatchedNotes = dirtyNotes.subtracting(writtenNotes)
            if !unmatchedNotes.isEmpty {
                dirtyTracker.markAllNotes(Array(unmatchedNotes))
            }
            if noteResult.result.hasFailures {
                workspace.reportVaultError(
                    title: "Couldn't save to vault",
                    message: noteResult.result.summaryMessage
                )
            }
        }

        if !dirtyCanvases.isEmpty {
            let allSnapshots = documents.snapshotAll(validIDs: workspace.allKnownFileIDs())
            let pending = allSnapshots.filter { dirtyCanvases.contains($0.key) }
            let historyAssetPaths = documents.referencedAssetPathsFromUndoHistory()
            let canvasResult = VaultFilesystem.writeCanvases(
                pending,
                vaultURL: vaultURL,
                additionalReferencedPaths: historyAssetPaths,
                referenceSnapshots: allSnapshots
            )
            let writtenCanvases = Set(pending.keys.filter { key in
                !canvasResult.failures.contains(where: { $0.path == key })
            })
            let unmatchedCanvases = dirtyCanvases.subtracting(writtenCanvases)
            if !unmatchedCanvases.isEmpty {
                dirtyTracker.markAllCanvases(Array(unmatchedCanvases))
            }
            if canvasResult.hasFailures {
                workspace.reportVaultError(
                    title: "Couldn't save to vault",
                    message: canvasResult.summaryMessage
                )
            }
        }
    }

    private struct DirtyNoteWriteOutcome {
        var result: VaultBatchWriteResult
        var writtenPaths: Set<String>
    }

    private func flushNoteToDisk(relativePath: String) {
        guard dirtyTracker.isNoteDirty(relativePath),
              let vault = workspace.activeVault else { return }
        workspace.suppressFilesystemWatch()
        let vaultURL = VaultSecurityAccess.resolvedURL(for: vault)
        documents.setVaultURL(vaultURL)
        let outcome = writeDirtyNotes([relativePath], vaultURL: vaultURL)
        if outcome.result.hasFailures {
            workspace.reportVaultError(
                title: "Couldn't save note",
                message: outcome.result.summaryMessage
            )
        }
        if outcome.writtenPaths.contains(relativePath) {
            dirtyTracker.clearNote(relativePath)
        }
    }

    private func flushCanvasToDisk(relativePath: String) {
        guard let vault = workspace.activeVault,
              let store = documents.loadedStore(for: relativePath) else { return }
        workspace.suppressFilesystemWatch()
        let vaultURL = VaultSecurityAccess.resolvedURL(for: vault)
        documents.setVaultURL(vaultURL)
        let snapshot = store.documentSnapshot
        do {
            try VaultFilesystem.writeCanvas(snapshot, relativePath: relativePath, vaultURL: vaultURL)
            dirtyTracker.clearCanvas(relativePath)
        } catch {
            workspace.reportVaultError(
                title: "Couldn't save canvas",
                message: error.localizedDescription
            )
        }
    }

    private func writeDirtyNotes(_ paths: Set<String>, vaultURL: URL) -> DirtyNoteWriteOutcome {
        var result = VaultBatchWriteResult()
        var writtenPaths = Set<String>()
        for file in workspace.files where file.kind == .note && paths.contains(file.relativePath) {
            do {
                try VaultFilesystem.writeNote(file, vaultURL: vaultURL)
                writtenPaths.insert(file.relativePath)
            } catch {
                result.failures.append((file.relativePath, error))
            }
        }
        return DirtyNoteWriteOutcome(result: result, writtenPaths: writtenPaths)
    }

    private func markEntireActiveVaultDirty() {
        let notePaths = workspace.files.filter { $0.kind == .note }.map(\.relativePath)
        let canvasPaths = workspace.files.filter { $0.kind == .canvas }.map(\.relativePath)
        dirtyTracker.markAllNotes(notePaths)
        dirtyTracker.markAllCanvases(canvasPaths)
        dirtyTracker.markWorkspaceState()
    }

    private func scheduleSave(urgency: CanvasSaveUrgency = .debounced) {
        if urgency == .structural {
            scheduledSaveUrgency = .structural
        } else if saveTask == nil {
            scheduledSaveUrgency = .debounced
        }

        saveTask?.cancel()
        workspace.markSaveStatus(.saving)
        let debounceNanoseconds: UInt64 = scheduledSaveUrgency == .structural ? 100_000_000 : 500_000_000
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushToDisk()
            self?.workspace.markSaveStatus(.saved)
            self?.scheduledSaveUrgency = .debounced
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.workspace.saveStatus == .saved {
                self?.workspace.markSaveStatus(.idle)
            }
        }
    }
}
