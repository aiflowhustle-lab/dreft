import Foundation
import Observation

/// Serialized contents of one canvas document (one `.canvas` file).
struct CanvasDocumentSnapshot: Codable {
    var cards: [CanvasCard]
    var edges: [CanvasEdge]
    var transform: CanvasViewTransform
}

/// One `CanvasStore` per canvas file, so each canvas tab shows its own document.
@Observable
final class CanvasDocumentRegistry {
    private var stores: [String: CanvasStore] = [:]
    /// Bumped when any canvas document mutates — drives autosave observation.
    private(set) var mutationGeneration = 0
    var onCanvasMutated: (() -> Void)?
    var onCanvasDirty: ((String) -> Void)?
    var onLinkedNoteBodyChanged: ((String, String) -> Void)?
    var vaultURL: URL?

    func store(for documentID: String) -> CanvasStore {
        if let existing = stores[documentID] {
            existing.vaultURL = vaultURL
            existing.documentRelativePath = documentID
            return existing
        }
        let store = CanvasStore()
        configure(store, documentID: documentID)
        stores[documentID] = store
        return store
    }

    private func configure(_ store: CanvasStore, documentID: String) {
        store.documentRelativePath = documentID
        store.vaultURL = vaultURL
        store.onDidMutate = { [weak self, weak store] in
            guard let self, let store else { return }
            self.mutationGeneration += 1
            if let path = store.documentRelativePath {
                self.onCanvasDirty?(path)
            }
            self.onCanvasMutated?()
        }
        store.onLinkedNoteBodyChanged = { [weak self] path, body in
            self?.onLinkedNoteBodyChanged?(path, body)
        }
    }

    func load(from snapshots: [String: CanvasDocumentSnapshot]) {
        stores.removeAll()
        for (documentID, snapshot) in snapshots {
            let store = CanvasStore()
            configure(store, documentID: documentID)
            store.applyDocumentSnapshot(snapshot)
            stores[documentID] = store
        }
    }

    func remove(documentID: String) {
        stores.removeValue(forKey: documentID)
    }

    func rekey(documentID oldID: String, to newID: String) {
        guard oldID != newID, let store = stores.removeValue(forKey: oldID) else { return }
        store.documentRelativePath = newID
        stores[newID] = store
    }

    func clear() {
        stores.removeAll()
    }

    /// Snapshots for persistence. `validIDs` filters out documents whose file was deleted.
    /// Known vault canvas files are always persisted, including when cleared to an empty document.
    func snapshotAll(validIDs: Set<String>? = nil) -> [String: CanvasDocumentSnapshot] {
        var result: [String: CanvasDocumentSnapshot] = [:]
        for (documentID, store) in stores {
            if let validIDs, !validIDs.contains(documentID) { continue }
            let snapshot = store.documentSnapshot
            let isDefault = snapshot.cards.isEmpty
                && snapshot.edges.isEmpty
                && snapshot.transform == CanvasViewTransform()
            if isDefault {
                guard let validIDs, validIDs.contains(documentID) else { continue }
            }
            result[documentID] = snapshot
        }
        return result
    }

    func migrateEmbeddedImages(vaultURL: URL) {
        for store in stores.values {
            store.migrateEmbeddedImages(vaultURL: vaultURL)
        }
    }

    func setVaultURL(_ url: URL?) {
        vaultURL = url
        for store in stores.values {
            store.vaultURL = url
        }
    }

    func applyCanvasSnapshots(_ snapshots: [String: CanvasDocumentSnapshot], validCanvasIDs: Set<String>) {
        for id in Set(stores.keys).subtracting(validCanvasIDs) {
            remove(documentID: id)
        }
        for (id, snapshot) in snapshots where validCanvasIDs.contains(id) {
            store(for: id).applyDocumentSnapshot(snapshot)
        }
    }

    func syncVaultFiles(_ entries: [WorkspaceFileEntry]) {
        for store in stores.values {
            store.setVaultFiles(entries)
        }
    }
}

extension CanvasStore {
    var documentSnapshot: CanvasDocumentSnapshot {
        CanvasDocumentSnapshot(cards: cards, edges: edges, transform: transform)
    }

    func applyDocumentSnapshot(_ snapshot: CanvasDocumentSnapshot) {
        // Re-syncs after our own saves deliver identical content; replacing the
        // document then would needlessly wipe undo history and yank the camera.
        if cards == snapshot.cards && edges == snapshot.edges {
            if transform == CanvasViewTransform() {
                // Fresh store that hasn't been viewed yet — adopt the saved camera.
                transform = snapshot.transform
            }
            return
        }
        cards = snapshot.cards
        edges = snapshot.edges
        transform = snapshot.transform
        clearUndoHistory()
    }
}
