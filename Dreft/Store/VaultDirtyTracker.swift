import Foundation

/// Tracks which vault files need writing so saves touch only changed documents.
struct VaultDirtyTracker {
    private(set) var dirtyNotePaths: Set<String> = []
    private(set) var dirtyCanvasPaths: Set<String> = []
    private(set) var workspaceStateDirty = false

    var hasPendingVaultWrites: Bool {
        !dirtyNotePaths.isEmpty || !dirtyCanvasPaths.isEmpty
    }

    mutating func markNote(_ relativePath: String) {
        dirtyNotePaths.insert(relativePath)
    }

    mutating func markCanvas(_ relativePath: String) {
        dirtyCanvasPaths.insert(relativePath)
    }

    mutating func markWorkspaceState() {
        workspaceStateDirty = true
    }

    mutating func markAllCanvases(_ relativePaths: [String]) {
        dirtyCanvasPaths.formUnion(relativePaths)
    }

    mutating func markAllNotes(_ relativePaths: [String]) {
        dirtyNotePaths.formUnion(relativePaths)
    }

    mutating func consumeNotes() -> Set<String> {
        let pending = dirtyNotePaths
        dirtyNotePaths.removeAll()
        return pending
    }

    mutating func consumeCanvases() -> Set<String> {
        let pending = dirtyCanvasPaths
        dirtyCanvasPaths.removeAll()
        return pending
    }

    mutating func consumeWorkspaceState() -> Bool {
        let pending = workspaceStateDirty
        workspaceStateDirty = false
        return pending
    }

    mutating func markEverythingDirty(notePaths: [String], canvasPaths: [String]) {
        markAllNotes(notePaths)
        markAllCanvases(canvasPaths)
        markWorkspaceState()
    }
}
