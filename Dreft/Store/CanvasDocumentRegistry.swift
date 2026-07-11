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
    var vaultURL: URL?

    func store(for documentID: String) -> CanvasStore {
        if let existing = stores[documentID] {
            existing.vaultURL = vaultURL
            return existing
        }
        let store = CanvasStore()
        store.onDidMutate = { [weak self] in
            guard let self else { return }
            self.mutationGeneration += 1
            self.onCanvasMutated?()
        }
        store.vaultURL = vaultURL
        stores[documentID] = store
        return store
    }

    func load(from snapshots: [String: CanvasDocumentSnapshot]) {
        stores.removeAll()
        for (documentID, snapshot) in snapshots {
            let store = CanvasStore()
            store.onDidMutate = { [weak self] in
                guard let self else { return }
                self.mutationGeneration += 1
                self.onCanvasMutated?()
            }
            store.vaultURL = vaultURL
            store.applyDocumentSnapshot(snapshot)
            stores[documentID] = store
        }
    }

    func remove(documentID: String) {
        stores.removeValue(forKey: documentID)
    }

    func rekey(documentID oldID: String, to newID: String) {
        guard oldID != newID, let store = stores.removeValue(forKey: oldID) else { return }
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
        cards = snapshot.cards
        edges = snapshot.edges
        transform = snapshot.transform
        clearUndoHistory()
    }
}
