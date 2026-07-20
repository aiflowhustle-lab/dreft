import CoreGraphics
import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@Observable
final class CanvasStore {
    var transform = CanvasViewTransform()
    var cards: [CanvasCard] = []
    var edges: [CanvasEdge] = []
    var selectedCardID: String?
    var selectedEdgeID: String?
    var hoverCardID: String?
    var isDragOver = false
    var vaultSearchQuery = ""
    var vaultSelectedIndex = 0
    var isVaultOpen = false
    /// Last rendered canvas size, used by viewport-only image export.
    var viewportSize: CGSize = .zero
  /// Bumped when async image thumbnails finish decoding — refreshes card views.
  var imageCacheRevision = 0

    var connectingFrom: (cardID: String, side: CanvasSide, toX: CGFloat, toY: CGFloat)?
    var isConnectingLine = false
    private(set) var connectOrigin: (cardID: String, side: CanvasSide)?
    /// When set, the user is dragging an existing edge endpoint to reconnect it.
    var editingEdgeID: String?
    /// Saved link target while dragging a linked endpoint so a no-op release can restore it.
    private var editingEdgeRestoreLink: (toID: String, toSide: CanvasSide)?

    var backlinkCount: Int { edges.count }

    enum ContextMenuKind: Equatable {
        case canvas(worldX: CGFloat, worldY: CGFloat)
        case handle(cardID: String, side: CanvasSide)
        case endpoint(edgeID: String, worldX: CGFloat, worldY: CGFloat)
        case edge(edgeID: String)
    }

    var contextMenu: (screenPoint: CGPoint, kind: ContextMenuKind)?
    /// When set, the next vault pick attaches to this dangling edge.
    var pendingEndpointEdgeID: String?
    /// World-space center of the add-card menu for the pending endpoint.
    var pendingEndpointMenuCenter: CGPoint?
    /// Note card that should receive keyboard focus after creation.
    var focusCardID: String?
    /// Fired after any document mutation (cards, edges, transform).
    var onDidMutate: (() -> Void)?
    /// When a linked note card (Obsidian `file` node) is edited, write body to the vault `.md` file.
    var onLinkedNoteBodyChanged: ((String, String) -> Void)?
    /// Relative path of the open `.canvas` file — used for per-file saves.
    var documentRelativePath: String?
    /// Vault folder used to store canvas image assets on disk.
    var vaultURL: URL?

    private struct CanvasDocumentState: Equatable {
        var cards: [CanvasCard]
        var edges: [CanvasEdge]
        var transform: CanvasViewTransform
        var selectedCardID: String?
        var selectedEdgeID: String?
    }

    @ObservationIgnored private var undoStack: [CanvasDocumentState] = []
    @ObservationIgnored private var redoStack: [CanvasDocumentState] = []
    @ObservationIgnored private var isRestoringHistory = false
    @ObservationIgnored private var suppressOverlayContentCommit = false
    @ObservationIgnored private var contentEditSessionCardID: String?
    @ObservationIgnored private var contentEditLastChange: Date?
    @ObservationIgnored private var contentEditPersistTask: Task<Void, Never>?
    @ObservationIgnored private var vaultFiles: [VaultFile] = []
    private(set) var historyRevision = 0

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    @ObservationIgnored private var cachedSpatialIndex: CanvasSpatialIndex?
    @ObservationIgnored private var cachedSpatialIndexRevision: Int = -1

    /// Spatial index for viewport culling on large canvases; nil when card count is small.
    func spatialIndexForCulling() -> CanvasSpatialIndex? {
        guard cards.count >= CanvasSpatialIndex.minimumCardCount else { return nil }
        if cachedSpatialIndexRevision != historyRevision {
            cachedSpatialIndex = CanvasSpatialIndex(cards: cards)
            cachedSpatialIndexRevision = historyRevision
        }
        return cachedSpatialIndex
    }

    private func notifyMutated(persistToDisk: Bool = true) {
        guard persistToDisk else { return }
        onDidMutate?()
    }

    private func captureState() -> CanvasDocumentState {
        CanvasDocumentState(
            cards: cards,
            edges: edges,
            transform: transform,
            selectedCardID: selectedCardID,
            selectedEdgeID: selectedEdgeID
        )
    }

    private func restoreState(_ state: CanvasDocumentState) {
        cards = state.cards
        edges = state.edges
        transform = state.transform
        selectedCardID = state.selectedCardID
        selectedEdgeID = state.selectedEdgeID
    }

    private func recordUndoCheckpoint() {
        guard !isRestoringHistory else { return }
        undoStack.append(captureState())
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
        historyRevision += 1
    }

    private func withUndo(_ action: () -> Void) {
        guard !isRestoringHistory else {
            action()
            return
        }
        recordUndoCheckpoint()
        action()
    }

    func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        endContentEdit()
        historyRevision += 1
    }

    func beginContentEdit(for id: String) {
        guard cards.contains(where: { $0.id == id }) else { return }
        if contentEditSessionCardID == id { return }
        endContentEdit()
        contentEditSessionCardID = id
        contentEditLastChange = nil
    }

    func endContentEdit(skipPersist: Bool = false) {
        let hadSession = contentEditSessionCardID != nil
        contentEditPersistTask?.cancel()
        contentEditSessionCardID = nil
        contentEditLastChange = nil
        if hadSession, !skipPersist {
            notifyMutated()
        }
    }

    /// Ends an open note edit when the user selects a different card.
    func selectCard(_ id: String?) {
        if let id, focusCardID != nil, focusCardID != id {
            endContentEdit()
            focusCardID = nil
        }
        selectedCardID = id
        if id != nil {
            selectedEdgeID = nil
        }
    }

    /// Replace the whole document (version-history restore) as an undoable step,
    /// so the user can always get back to what they had before restoring.
    func restoreDocumentSnapshot(_ snapshot: CanvasDocumentSnapshot) {
        withUndo {
            cards = snapshot.cards
            edges = snapshot.edges
            transform = snapshot.transform
        }
        selectedCardID = nil
        selectedEdgeID = nil
        focusCardID = nil
        endContentEdit()
        notifyMutated()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        suppressOverlayContentCommit = true
        endContentEdit(skipPersist: true)
        focusCardID = nil
        redoStack.append(captureState())
        isRestoringHistory = true
        restoreState(previous)
        isRestoringHistory = false
        historyRevision += 1
        NotePreviewCache.invalidateAll()
        schedulePersistenceAfterHistoryStep()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.suppressOverlayContentCommit = false
        }
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        suppressOverlayContentCommit = true
        endContentEdit(skipPersist: true)
        focusCardID = nil
        undoStack.append(captureState())
        isRestoringHistory = true
        restoreState(next)
        isRestoringHistory = false
        historyRevision += 1
        NotePreviewCache.invalidateAll()
        schedulePersistenceAfterHistoryStep()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.suppressOverlayContentCommit = false
        }
    }

    /// Updates the canvas immediately, then saves on the next run loop so undo/redo feels instant.
    private func schedulePersistenceAfterHistoryStep() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.onDidMutate?()
        }
    }

    let cardColors: [(name: String, hex: String)] = [
        ("Default", ""), ("Red", "#FB464C"), ("Orange", "#E9973F"),
        ("Yellow", "#E0DE71"), ("Green", "#44CF6E"), ("Cyan", "#53DFDD"),
        ("Purple", "#A882FF"),
    ]

    // MARK: - Transform

    func screenToWorld(_ point: CGPoint, in size: CGSize) -> CGPoint {
        screenToWorld(point, in: size, transform: transform)
    }

    func screenToWorld(_ point: CGPoint, in size: CGSize, transform: CanvasViewTransform) -> CGPoint {
        CGPoint(
            x: (point.x - transform.x) / transform.zoom,
            y: (point.y - transform.y) / transform.zoom
        )
    }

    func worldToScreen(_ point: CGPoint, transform: CanvasViewTransform) -> CGPoint {
        CGPoint(
            x: point.x * transform.zoom + transform.x,
            y: point.y * transform.zoom + transform.y
        )
    }

    func worldToScreen(_ point: CGPoint) -> CGPoint {
        worldToScreen(point, transform: transform)
    }

    func zoom(at anchor: CGPoint, factor: CGFloat) {
        let newZoom = min(CanvasViewTransform.maxZoom, max(CanvasViewTransform.minZoom, transform.zoom * factor))
        let ratio = newZoom / transform.zoom
        transform.x = anchor.x - (anchor.x - transform.x) * ratio
        transform.y = anchor.y - (anchor.y - transform.y) * ratio
        transform.zoom = newZoom
        notifyMutated()
    }

    func zoomToCard(_ card: CanvasCard, canvasSize: CGSize) {
        selectedCardID = card.id
        zoomToSelection(canvasSize: canvasSize)
    }

    /// Fits the canvas, skipping note cards that sit far from the main content.
    func zoomToFit(canvasSize: CGSize, padding: CGFloat = 80) {
        guard !cards.isEmpty else {
            transform = CanvasViewTransform()
            notifyMutated()
            return
        }
        applyZoomFit(to: cardIDsForZoomToFit(), canvasSize: canvasSize, padding: padding)
    }

    /// Obsidian `Shift+2` — frame the selected card (and its dangling edges).
    func zoomToSelection(canvasSize: CGSize, padding: CGFloat = 80) {
        guard let selectedID = selectedCardID else { return }
        applyZoomFit(to: Set([selectedID]), canvasSize: canvasSize, padding: padding)
    }

    /// Frame the connection path and its linked cards.
    func zoomToEdge(_ edgeID: String, canvasSize: CGSize, padding: CGFloat = 100) {
        guard let edge = edges.first(where: { $0.id == edgeID }),
              let from = cards.first(where: { $0.id == edge.fromID }),
              let endpoint = edgeEndpoint(for: edge) else { return }

        let p1 = CanvasGeometry.anchor(for: from, side: edge.fromSide, overrides: [:])
        var bounds = CGRect.null
        for index in 0...28 {
            let t = CGFloat(index) / 28
            let point = CanvasGeometry.pointOnCurve(
                from: p1,
                fromSide: edge.fromSide,
                to: endpoint.point,
                toSide: endpoint.toSide,
                t: t
            )
            bounds = bounds.union(CGRect(x: point.x - 40, y: point.y - 40, width: 80, height: 80))
        }
        let fromRect = CGRect(x: from.x, y: from.y, width: from.width, height: from.height)
        bounds = bounds.union(fromRect)
        if let toID = edge.toID, let to = cards.first(where: { $0.id == toID }) {
            bounds = bounds.union(CGRect(x: to.x, y: to.y, width: to.width, height: to.height))
        }
        guard bounds.width > 1, bounds.height > 1 else { return }
        transform = fitTransform(to: bounds, canvasSize: canvasSize, padding: padding)
        notifyMutated()
    }

    func setEdgeLabel(_ edgeID: String, label: String) {
        guard let index = edges.firstIndex(where: { $0.id == edgeID }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? nil : trimmed
        guard edges[index].label != resolved else { return }
        withUndo {
            edges[index].label = resolved
        }
        notifyMutated()
    }

    func setEdgeColor(_ edgeID: String, hex: String) {
        guard let index = edges.firstIndex(where: { $0.id == edgeID }) else { return }
        let resolved = hex.isEmpty ? nil : hex
        guard edges[index].colorHex != resolved else { return }
        withUndo {
            edges[index].colorHex = resolved
        }
        notifyMutated()
    }

    private func applyZoomFit(to cardIDs: Set<String>, canvasSize: CGSize, padding: CGFloat) {
        let bounds = contentBounds(for: cardIDs, includeDanglingEdges: true, edgePadding: 24)
        guard bounds.width > 1, bounds.height > 1 else { return }
        transform = fitTransform(to: bounds, canvasSize: canvasSize, padding: padding)
        notifyMutated()
    }

    /// All cards except note cards that are far from everything else on the canvas.
    private func cardIDsForZoomToFit() -> Set<String> {
        let notes = cards.filter { $0.kind == .note }
        let anchors = cards.filter { $0.kind != .note }

        if anchors.isEmpty {
            return Set(cards.map(\.id))
        }

        var included = Set(anchors.map(\.id))
        for note in notes where !isDistantNoteCard(note, comparedTo: anchors) {
            included.insert(note.id)
        }
        return included
    }

    private func isDistantNoteCard(_ note: CanvasCard, comparedTo anchors: [CanvasCard]) -> Bool {
        let noteCenter = cardCenter(note)
        var nearest = CGFloat.greatestFiniteMagnitude
        for anchor in anchors {
            nearest = min(nearest, hypot(noteCenter.x - cardCenter(anchor).x, noteCenter.y - cardCenter(anchor).y))
        }
        let threshold = max(720, typicalCardSpacing(anchors) * 4)
        return nearest > threshold
    }

    private func cardCenter(_ card: CanvasCard) -> CGPoint {
        CGPoint(x: card.x + card.width / 2, y: card.y + card.height / 2)
    }

    private func typicalCardSpacing(_ cards: [CanvasCard]) -> CGFloat {
        guard cards.count > 1 else { return 240 }
        var nearestNeighbor: [CGFloat] = []
        let centers = cards.map(cardCenter)
        for (index, center) in centers.enumerated() {
            var nearest = CGFloat.greatestFiniteMagnitude
            for (otherIndex, other) in centers.enumerated() where otherIndex != index {
                nearest = min(nearest, hypot(center.x - other.x, center.y - other.y))
            }
            nearestNeighbor.append(nearest)
        }
        nearestNeighbor.sort()
        return nearestNeighbor[nearestNeighbor.count / 2]
    }

    private func contentBounds(
        for cardIDs: Set<String>,
        includeDanglingEdges: Bool,
        edgePadding: CGFloat
    ) -> CGRect {
        var bounds = CGRect.null
        for card in cards where cardIDs.contains(card.id) {
            bounds = bounds.union(CGRect(x: card.x, y: card.y, width: card.width, height: card.height))
        }
        if includeDanglingEdges {
            for edge in edges where cardIDs.contains(edge.fromID) {
                if let point = edge.toPoint {
                    bounds = bounds.union(
                        CGRect(
                            x: point.x - edgePadding,
                            y: point.y - edgePadding,
                            width: edgePadding * 2,
                            height: edgePadding * 2
                        )
                    )
                }
            }
        }
        return bounds
    }

    private func fitTransform(
        to bounds: CGRect,
        canvasSize: CGSize,
        padding: CGFloat
    ) -> CanvasViewTransform {
        let zoomX = (canvasSize.width - padding * 2) / bounds.width
        let zoomY = (canvasSize.height - padding * 2) / bounds.height
        let zoom = min(
            CanvasViewTransform.maxZoom,
            max(CanvasViewTransform.minZoom, min(zoomX, zoomY))
        )
        return CanvasViewTransform(
            x: canvasSize.width / 2 - bounds.midX * zoom,
            y: canvasSize.height / 2 - bounds.midY * zoom,
            zoom: zoom
        )
    }

    // MARK: - Cards

    func addCard(kind: CardKind, at center: CGPoint) {
        withUndo {
            let card = CanvasCard.make(kind: kind, at: center)
            cards.append(card)
            selectedCardID = card.id
        }
        notifyMutated()
    }

    func addCompactNote(at center: CGPoint) {
        withUndo {
            let card = CanvasCard.makeCompactNote(at: center)
            cards.append(card)
            selectedCardID = card.id
        }
        notifyMutated()
    }

    func addCompactNoteAtCenter(canvasSize: CGSize, transform: CanvasViewTransform? = nil) {
        let t = transform ?? self.transform
        let center = screenToWorld(
            CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
            in: canvasSize,
            transform: t
        )
        addCompactNote(at: center)
    }

    func addCardAtCenter(kind: CardKind, canvasSize: CGSize, transform: CanvasViewTransform? = nil) {
        let t = transform ?? self.transform
        let center = screenToWorld(CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2), in: canvasSize, transform: t)
        addCard(kind: kind, at: center)
    }

    func addImageCard(data: Data, title: String?, topLeft: CGPoint) {
        withUndo {
            let id = UUID().uuidString
            let pixelSize = ImagePixelSize.from(data: data) ?? CGSize(width: 320, height: 220)
            let displaySize = CanvasLayout.displaySize(for: pixelSize)

            let content: String
            if let vaultURL {
                content = (try? VaultFilesystem.saveCanvasImage(
                    data: data,
                    vaultURL: vaultURL,
                    suggestedName: title
                )) ?? data.base64EncodedString()
            } else {
                content = data.base64EncodedString()
            }

            cards.append(CanvasCard(
                id: id,
                kind: .image,
                x: topLeft.x,
                y: topLeft.y,
                width: displaySize.width,
                height: displaySize.height,
                content: content,
                title: Self.resolvedImageTitle(title),
                createdAt: Date()
            ))
            selectedCardID = id

            Task {
                await CanvasImageCache.shared.prepareDisplayImage(data: data, cardID: id, contentKey: content)
                await MainActor.run { imageCacheRevision += 1 }
            }
        }
        notifyMutated()
    }

    #if canImport(UIKit)
    func addImageCard(image: UIImage, title: String?, topLeft: CGPoint) {
        guard let data = image.pngData() else { return }
        addImageCard(data: data, title: title, topLeft: topLeft)
    }
    #endif

    #if canImport(AppKit)
    func addImageCard(image: NSImage, title: String?, topLeft: CGPoint) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return }
        addImageCard(data: data, title: title, topLeft: topLeft)
    }
    #endif

    func deleteCard(_ id: String) {
        withUndo {
            if contentEditSessionCardID == id { endContentEdit() }
            CanvasImageCache.shared.remove(cardID: id)
            cards.removeAll { $0.id == id }
            edges.removeAll { $0.fromID == id || $0.toID == id }
            if selectedCardID == id { selectedCardID = nil }
        }
        notifyMutated()
    }

    func swapImageCard(_ id: String, data: Data, suggestedTitle: String?) {
        guard let index = cards.firstIndex(where: { $0.id == id }),
              cards[index].kind == .image,
              let vaultURL else { return }

        withUndo {
            let content = cards[index].content
            if VaultFilesystem.isEmbeddedImageContent(content) {
                if let path = try? VaultFilesystem.saveCanvasImage(
                    data: data,
                    vaultURL: vaultURL,
                    suggestedName: suggestedTitle ?? cards[index].title
                ) {
                    cards[index].content = path
                }
            } else {
                let url = vaultURL.appendingPathComponent(content)
                try? data.write(to: url, options: .atomic)
            }

            if let suggestedTitle, !suggestedTitle.isEmpty {
                cards[index].title = (suggestedTitle as NSString).deletingPathExtension
            }

            let pixelSize = ImagePixelSize.from(data: data) ?? CGSize(width: 320, height: 220)
            let displaySize = CanvasLayout.displaySize(for: pixelSize)
            cards[index].width = displaySize.width
            cards[index].height = displaySize.height

            let contentKey = cards[index].content
            Task {
                await CanvasImageCache.shared.prepareDisplayImage(data: data, cardID: id, contentKey: contentKey)
                await MainActor.run { imageCacheRevision += 1 }
            }
        }
        notifyMutated()
    }

    func imageRelativePath(for card: CanvasCard) -> String? {
        guard card.kind == .image, !VaultFilesystem.isEmbeddedImageContent(card.content) else { return nil }
        return card.content
    }

    func imageFileURL(for card: CanvasCard) -> URL? {
        guard let relativePath = imageRelativePath(for: card),
              let vaultURL else { return nil }
        return vaultURL.appendingPathComponent(relativePath)
    }

    /// Converts legacy base64 image cards to files in `.dreft/assets/`.
    func migrateEmbeddedImages(vaultURL: URL) {
        var changed = false
        for index in cards.indices {
            guard cards[index].kind == .image else { continue }
            let content = cards[index].content
            guard VaultFilesystem.isEmbeddedImageContent(content),
                  let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters),
                  let path = try? VaultFilesystem.saveCanvasImage(
                    data: data,
                    vaultURL: vaultURL,
                    suggestedName: cards[index].title
                  ) else { continue }
            cards[index].content = path
            changed = true
            Task {
                await CanvasImageCache.shared.prepareDisplayImage(data: data, cardID: cards[index].id, contentKey: path)
                await MainActor.run { imageCacheRevision += 1 }
            }
        }
        if changed { notifyMutated() }
    }

    func updateContent(for id: String, content: String, fromTextUndo: Bool = false) {
        guard !isRestoringHistory, !suppressOverlayContentCommit else { return }
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        if contentEditSessionCardID != id {
            beginContentEdit(for: id)
        }
        if !fromTextUndo, shouldRecordContentCheckpoint() {
            recordUndoCheckpoint()
        }
        contentEditLastChange = Date()

        if let linkedPath = CanvasCardContent.linkedNotePath(for: cards[index]) {
            onLinkedNoteBodyChanged?(linkedPath, content)
        } else {
            cards[index].content = content
            notifyMutated(persistToDisk: false)
            scheduleDebouncedContentPersist()
        }
    }

    /// Groups typing into undo steps separated by ~400ms pauses.
    private func shouldRecordContentCheckpoint() -> Bool {
        guard let last = contentEditLastChange else { return true }
        return Date().timeIntervalSince(last) > 0.4
    }

    /// Saves in-progress note edits without spamming the vault pipeline on every keystroke.
    private func scheduleDebouncedContentPersist() {
        contentEditPersistTask?.cancel()
        contentEditPersistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, self?.contentEditSessionCardID != nil else { return }
            self?.notifyMutated()
        }
    }

    func updateTitle(for id: String, title: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? Self.defaultImageTitle : trimmed
        guard cards[index].title != resolved else { return }
        withUndo {
            cards[index].title = resolved
        }
        notifyMutated()
    }

    /// Display name for an image card, never the bare placeholder "Image".
    func displayTitle(for card: CanvasCard) -> String {
        if let title = card.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let path = imageRelativePath(for: card) {
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if !stem.isEmpty { return stem }
        }
        return Self.defaultImageTitle
    }

    static let defaultImageTitle = "Untitled image"

    static func resolvedImageTitle(_ title: String?) -> String {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return defaultImageTitle
        }
        return (title as NSString).deletingPathExtension
    }

    func moveCard(_ id: String, to origin: CGPoint) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let card = cards[index]
        guard card.x != origin.x || card.y != origin.y else { return }
        withUndo {
            cards[index].x = origin.x
            cards[index].y = origin.y
        }
        notifyMutated()
    }

    func resizeCard(_ id: String, frame: CGRect) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let card = cards[index]
        let resolved = CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: max(48, frame.width),
            height: max(48, frame.height)
        )
        guard card.x != resolved.origin.x
            || card.y != resolved.origin.y
            || card.width != resolved.width
            || card.height != resolved.height else { return }
        withUndo {
            cards[index].x = resolved.origin.x
            cards[index].y = resolved.origin.y
            cards[index].width = resolved.width
            cards[index].height = resolved.height
        }
        notifyMutated()
    }

    func setCardColor(_ id: String, hex: String) {
        withUndo {
            guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
            cards[index].colorHex = hex.isEmpty ? nil : hex
        }
        notifyMutated()
    }

    func setTransform(_ newTransform: CanvasViewTransform) {
        guard transform != newTransform else { return }
        transform = newTransform
        notifyMutated()
    }

    func card(
        at point: CGPoint,
        excluding excludedID: String? = nil,
        positionOverrides: [String: CGPoint] = [:],
        resizeOverrides: [String: CGRect] = [:],
        padding: CGFloat = 20
    ) -> CanvasCard? {
        cards.reversed().first { card in
            guard card.id != excludedID else { return false }
            let rect = CanvasGeometry.cardRect(card, overrides: positionOverrides, resizeOverrides: resizeOverrides)
            return rect.insetBy(dx: -padding, dy: -padding).contains(point)
        }
    }

    func cardRect(
        for id: String,
        positionOverrides: [String: CGPoint] = [:],
        resizeOverrides: [String: CGRect] = [:]
    ) -> CGRect? {
        guard let card = cards.first(where: { $0.id == id }) else { return nil }
        return CanvasGeometry.cardRect(card, overrides: positionOverrides, resizeOverrides: resizeOverrides)
    }

    // MARK: - Connections

    func beginConnecting(
        fromID: String,
        side: CanvasSide,
        positionOverrides: [String: CGPoint] = [:],
        resizeOverrides: [String: CGRect] = [:]
    ) {
        editingEdgeID = nil
        guard let card = cards.first(where: { $0.id == fromID }) else { return }
        connectOrigin = (fromID, side)
        isConnectingLine = true
        let rect = CanvasGeometry.cardRect(card, overrides: positionOverrides, resizeOverrides: resizeOverrides)
        let anchor = CanvasGeometry.anchor(in: rect, side: side)
        connectingFrom = (fromID, side, anchor.x, anchor.y)
    }

    func updateConnecting(
        to point: CGPoint,
        positionOverrides: [String: CGPoint] = [:],
        resizeOverrides: [String: CGRect] = [:]
    ) {
        if let editingID = editingEdgeID,
           let index = edges.firstIndex(where: { $0.id == editingID }) {
            let edge = edges[index]
            edges[index].toPoint = point
            edges[index].toID = nil
            edges[index].toSide = nil
            connectingFrom = (edge.fromID, edge.fromSide, point.x, point.y)
            hoverCardID = card(
                at: point,
                excluding: edge.fromID,
                positionOverrides: positionOverrides,
                resizeOverrides: resizeOverrides
            )?.id
            return
        }

        guard let origin = connectOrigin else { return }
        connectingFrom = (origin.cardID, origin.side, point.x, point.y)
        hoverCardID = card(
            at: point,
            excluding: origin.cardID,
            positionOverrides: positionOverrides,
            resizeOverrides: resizeOverrides
        )?.id
    }

    func finishConnecting(
        at point: CGPoint,
        moved: Bool,
        screenPoint: CGPoint,
        positionOverrides: [String: CGPoint] = [:],
        resizeOverrides: [String: CGRect] = [:]
    ) {
        if let editingID = editingEdgeID,
           let index = edges.firstIndex(where: { $0.id == editingID }) {
            let edge = edges[index]
            defer {
                editingEdgeID = nil
                clearConnecting()
            }

            if let targetID = card(
                at: point,
                excluding: edge.fromID,
                positionOverrides: positionOverrides,
                resizeOverrides: resizeOverrides
            )?.id ?? hoverCardID,
               let target = cards.first(where: { $0.id == targetID }) {
                let rect = CanvasGeometry.cardRect(target, overrides: positionOverrides, resizeOverrides: resizeOverrides)
                withUndo {
                    edges[index].toID = targetID
                    edges[index].toSide = CanvasGeometry.nearestSide(for: point, in: rect)
                    edges[index].toPoint = nil
                }
                notifyMutated()
                return
            }

            if !moved, let restore = editingEdgeRestoreLink {
                withUndo {
                    edges[index].toID = restore.toID
                    edges[index].toSide = restore.toSide
                    edges[index].toPoint = nil
                }
                notifyMutated()
                return
            }

            withUndo {
                edges[index].toID = nil
                edges[index].toSide = nil
                edges[index].toPoint = point
            }
            if moved {
                showEndpointMenu(
                    edgeID: editingID,
                    worldPoint: point,
                    screenPoint: screenPoint
                )
            }
            notifyMutated()
            return
        }

        guard let origin = connectOrigin else {
            clearConnecting()
            return
        }

        if let targetID = card(
            at: point,
            excluding: origin.cardID,
            positionOverrides: positionOverrides,
            resizeOverrides: resizeOverrides
        )?.id ?? hoverCardID,
           let target = cards.first(where: { $0.id == targetID }) {
            let rect = CanvasGeometry.cardRect(target, overrides: positionOverrides, resizeOverrides: resizeOverrides)
            connect(
                fromID: origin.cardID,
                fromSide: origin.side,
                toID: target.id,
                toSide: CanvasGeometry.nearestSide(for: point, in: rect)
            )
        } else if moved {
            showEndpointMenu(
                edgeID: connectToPoint(fromID: origin.cardID, fromSide: origin.side, point: point),
                worldPoint: point,
                screenPoint: screenPoint
            )
        } else if let from = cards.first(where: { $0.id == origin.cardID }) {
            let rect = CanvasGeometry.cardRect(from, overrides: positionOverrides, resizeOverrides: resizeOverrides)
            let anchor = CanvasGeometry.anchor(in: rect, side: origin.side)
            let normal = origin.side.normal(dx: 0, dy: 0)
            let defaultPoint = CGPoint(
                x: anchor.x + normal.x * CanvasConstants.defaultConnectDistance,
                y: anchor.y + normal.y * CanvasConstants.defaultConnectDistance
            )
            showEndpointMenu(
                edgeID: connectToPoint(fromID: origin.cardID, fromSide: origin.side, point: defaultPoint),
                worldPoint: defaultPoint,
                screenPoint: screenPoint
            )
        } else {
            clearConnecting()
        }
    }

    func showEndpointMenu(edgeID: String, worldPoint: CGPoint, screenPoint: CGPoint) {
        contextMenu = (screenPoint, .endpoint(edgeID: edgeID, worldX: worldPoint.x, worldY: worldPoint.y))
    }

    func showEdgeMenu(edgeID: String, screenPoint: CGPoint) {
        selectedEdgeID = edgeID
        selectedCardID = nil
        contextMenu = (screenPoint, .edge(edgeID: edgeID))
    }

    func showCanvasMenu(at screenPoint: CGPoint, worldPoint: CGPoint) {
        dismissPendingEndpoint()
        contextMenu = (screenPoint, .canvas(worldX: worldPoint.x, worldY: worldPoint.y))
    }

    func selectEdge(_ edgeID: String) {
        selectedEdgeID = edgeID
        selectedCardID = nil
        contextMenu = nil
    }

    func setEdgeDirection(_ edgeID: String, direction: CanvasEdgeDirection) {
        guard let index = edges.firstIndex(where: { $0.id == edgeID }),
              edges[index].direction != direction else { return }
        withUndo {
            edges[index].direction = direction
        }
        selectedEdgeID = edgeID
        notifyMutated()
    }

    /// Apply direction to every edge touching this card (including dangling lines).
    func setConnectedEdgeDirection(forCard cardID: String, direction: CanvasEdgeDirection) {
        let indexes = edges.indices.filter { i in
            let edge = edges[i]
            return edge.fromID == cardID || edge.toID == cardID
        }
        guard !indexes.isEmpty else { return }
        withUndo {
            for i in indexes {
                edges[i].direction = direction
            }
        }
        if let first = indexes.first {
            selectedEdgeID = edges[first].id
        }
        notifyMutated()
    }

    func deleteEdge(_ id: String) {
        withUndo {
            edges.removeAll { $0.id == id }
            if selectedEdgeID == id { selectedEdgeID = nil }
            if editingEdgeID == id {
                editingEdgeID = nil
                clearConnecting()
            }
            if case .endpoint(let edgeID, _, _) = contextMenu?.kind, edgeID == id {
                contextMenu = nil
            }
            if case .edge(let edgeID) = contextMenu?.kind, edgeID == id {
                contextMenu = nil
            }
            if pendingEndpointEdgeID == id {
                pendingEndpointEdgeID = nil
                pendingEndpointMenuCenter = nil
            }
        }
        notifyMutated()
    }

    /// Detach a linked endpoint and begin dragging it to reconnect elsewhere.
    func beginEditingEdgeEndpoint(
        _ edgeID: String,
        positionOverrides: [String: CGPoint] = [:],
        resizeOverrides: [String: CGRect] = [:]
    ) {
        guard let index = edges.firstIndex(where: { $0.id == edgeID }),
              cards.first(where: { $0.id == edges[index].fromID }) != nil else { return }

        let tip: CGPoint
        let shouldDetachLink: Bool
        var restoreLink: (toID: String, toSide: CanvasSide)?
        if let toID = edges[index].toID,
           let to = cards.first(where: { $0.id == toID }) {
            let rect = CanvasGeometry.cardRect(to, overrides: positionOverrides, resizeOverrides: resizeOverrides)
            let side = edges[index].toSide ?? edges[index].fromSide.opposite
            tip = CanvasGeometry.anchor(in: rect, side: side)
            shouldDetachLink = true
            restoreLink = (toID, side)
        } else if let point = edges[index].toPoint {
            tip = point
            shouldDetachLink = false
            restoreLink = nil
        } else {
            return
        }

        if shouldDetachLink, let restoreLink {
            withUndo {
                editingEdgeRestoreLink = restoreLink
                edges[index].toID = nil
                edges[index].toSide = nil
                edges[index].toPoint = tip
                editingEdgeID = edgeID
                connectOrigin = (edges[index].fromID, edges[index].fromSide)
                isConnectingLine = true
                connectingFrom = (edges[index].fromID, edges[index].fromSide, tip.x, tip.y)
                hoverCardID = nil
                selectedCardID = nil
            }
        } else {
            editingEdgeRestoreLink = nil
            editingEdgeID = edgeID
            connectOrigin = (edges[index].fromID, edges[index].fromSide)
            isConnectingLine = true
            connectingFrom = (edges[index].fromID, edges[index].fromSide, tip.x, tip.y)
            hoverCardID = nil
            selectedCardID = nil
        }
    }

    func edgeEndpoint(
        for edge: CanvasEdge,
        positionOverrides: [String: CGPoint] = [:],
        resizeOverrides: [String: CGRect] = [:]
    ) -> (point: CGPoint, toSide: CanvasSide?)? {
        guard cards.contains(where: { $0.id == edge.fromID }) else { return nil }

        if let toID = edge.toID,
           let to = cards.first(where: { $0.id == toID }) {
            let rect = CanvasGeometry.cardRect(to, overrides: positionOverrides, resizeOverrides: resizeOverrides)
            let side = edge.toSide ?? edge.fromSide.opposite
            return (CanvasGeometry.anchor(in: rect, side: side), side)
        }
        if let point = edge.toPoint {
            return (point, nil)
        }
        return nil
    }

    private func clearConnecting() {
        connectOrigin = nil
        connectingFrom = nil
        hoverCardID = nil
        isConnectingLine = false
        editingEdgeID = nil
        editingEdgeRestoreLink = nil
    }

    func connect(fromID: String, fromSide: CanvasSide, toID: String, toSide: CanvasSide) {
        withUndo {
            edges.append(CanvasEdge(fromID: fromID, fromSide: fromSide, toID: toID, toSide: toSide))
            clearConnecting()
        }
        notifyMutated()
    }

    @discardableResult
    func connectToPoint(fromID: String, fromSide: CanvasSide, point: CGPoint) -> String {
        var edgeID = ""
        withUndo {
            let edge = CanvasEdge(fromID: fromID, fromSide: fromSide, toPoint: point)
            edges.append(edge)
            clearConnecting()
            edgeID = edge.id
        }
        notifyMutated()
        return edgeID
    }

    func addConnectedCard(fromID: String, fromSide: CanvasSide) {
        guard let from = cards.first(where: { $0.id == fromID }) else { return }
        withUndo {
            let gap: CGFloat = 120
            let width: CGFloat = 260
            let height: CGFloat = 160
            var origin = CGPoint(x: from.x, y: from.y)

            switch fromSide {
            case .right: origin = CGPoint(x: from.x + from.width + gap, y: from.y + from.height / 2 - height / 2)
            case .left: origin = CGPoint(x: from.x - width - gap, y: from.y + from.height / 2 - height / 2)
            case .bottom: origin = CGPoint(x: from.x + from.width / 2 - width / 2, y: from.y + from.height + gap)
            case .top: origin = CGPoint(x: from.x + from.width / 2 - width / 2, y: from.y - height - gap)
            }

            let card = CanvasCard(id: UUID().uuidString, kind: .note, x: origin.x, y: origin.y, width: width, height: height, content: "", createdAt: Date())
            cards.append(card)
            edges.append(CanvasEdge(fromID: fromID, fromSide: fromSide, toID: card.id, toSide: fromSide.opposite))
            selectedCardID = card.id
            contextMenu = nil
        }
        notifyMutated()
    }

    func attachCardToEndpoint(edgeID: String, cardID: String, toSide: CanvasSide? = nil) {
        guard let index = edges.firstIndex(where: { $0.id == edgeID }) else { return }
        edges[index].toID = cardID
        edges[index].toPoint = nil
        if let toSide {
            edges[index].toSide = toSide
        } else if edges[index].toSide == nil {
            edges[index].toSide = edges[index].fromSide.opposite
        }
    }

    /// Places a new note card centered where the add-card menu was shown.
    func addCardAtEndpoint(edgeID: String, atMenuCenter menuCenter: CGPoint) {
        guard let placement = endpointCardPlacement(for: edgeID, menuCenter: menuCenter) else { return }

        withUndo {
            let card = CanvasCard(
                id: UUID().uuidString,
                kind: .note,
                x: placement.origin.x,
                y: placement.origin.y,
                width: placement.width,
                height: placement.height,
                content: "",
                createdAt: Date()
            )
            cards.append(card)
            attachCardToEndpoint(edgeID: edgeID, cardID: card.id, toSide: placement.toSide)
            selectedCardID = card.id
            pendingEndpointMenuCenter = nil
            contextMenu = nil
        }
        notifyMutated()
    }

    func setVaultFiles(_ entries: [WorkspaceFileEntry]) {
        vaultFiles = VaultFile.openableFiles(from: entries)
    }

    func addVaultFile(_ file: VaultFile, canvasSize: CGSize) {
        if let edgeID = pendingEndpointEdgeID, let menuCenter = pendingEndpointMenuCenter {
            pendingEndpointEdgeID = nil
            pendingEndpointMenuCenter = nil
            addVaultFileAtEndpoint(file, edgeID: edgeID, menuCenter: menuCenter)
            return
        }

        switch file.kind {
        case .note, .canvas:
            insertVaultNoteCard(file, canvasSize: canvasSize)
        case .image:
            let center = screenToWorld(
                CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
                in: canvasSize
            )
            let topLeft: CGPoint
            if let vaultURL,
               let data = VaultFilesystem.imageData(at: file.relativePath, vaultURL: vaultURL) {
                let displaySize = CanvasLayout.displaySize(
                    for: ImagePixelSize.from(data: data) ?? CGSize(width: 320, height: 220)
                )
                topLeft = CGPoint(
                    x: center.x - displaySize.width / 2,
                    y: center.y - displaySize.height / 2
                )
            } else {
                topLeft = CGPoint(x: center.x - 130, y: center.y - 90)
            }
            insertVaultImageCard(file, topLeft: topLeft)
        case .folder:
            break
        }
    }

    private func addVaultFileAtEndpoint(_ file: VaultFile, edgeID: String, menuCenter: CGPoint) {
        guard let placement = endpointCardPlacement(for: edgeID, menuCenter: menuCenter) else { return }

        switch file.kind {
        case .note, .canvas:
            withUndo {
                let card = makeVaultNoteCard(file, origin: placement.origin, size: placement.size)
                cards.append(card)
                attachCardToEndpoint(edgeID: edgeID, cardID: card.id, toSide: placement.toSide)
                selectedCardID = card.id
                pendingEndpointMenuCenter = nil
                isVaultOpen = false
                contextMenu = nil
            }
            notifyMutated()
        case .image:
            insertVaultImageCard(
                file,
                topLeft: placement.origin,
                edgeID: edgeID,
                toSide: placement.toSide
            )
        case .folder:
            break
        }
    }

    private func insertVaultNoteCard(_ file: VaultFile, canvasSize: CGSize) {
        withUndo {
            let center = screenToWorld(
                CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
                in: canvasSize
            )
            let card = makeVaultNoteCard(
                file,
                origin: CGPoint(x: center.x - 130, y: center.y - 90),
                size: CGSize(width: 260, height: 180)
            )
            cards.append(card)
            selectedCardID = card.id
            isVaultOpen = false
        }
        notifyMutated()
    }

    private func insertVaultImageCard(
        _ file: VaultFile,
        topLeft: CGPoint,
        edgeID: String? = nil,
        toSide: CanvasSide? = nil
    ) {
        guard let vaultURL,
              let data = VaultFilesystem.imageData(at: file.relativePath, vaultURL: vaultURL) else { return }

        withUndo {
            let id = UUID().uuidString
            let pixelSize = ImagePixelSize.from(data: data) ?? CGSize(width: 320, height: 220)
            let displaySize = CanvasLayout.displaySize(for: pixelSize)

            cards.append(CanvasCard(
                id: id,
                kind: .image,
                x: topLeft.x,
                y: topLeft.y,
                width: displaySize.width,
                height: displaySize.height,
                content: file.relativePath,
                title: vaultDisplayName(for: file),
                createdAt: Date()
            ))
            selectedCardID = id

            if let edgeID, let toSide {
                attachCardToEndpoint(edgeID: edgeID, cardID: id, toSide: toSide)
            }

            Task {
                await CanvasImageCache.shared.prepareDisplayImage(
                    data: data,
                    cardID: id,
                    contentKey: file.relativePath
                )
                await MainActor.run { imageCacheRevision += 1 }
            }

            isVaultOpen = false
            pendingEndpointMenuCenter = nil
            contextMenu = nil
        }
        notifyMutated()
    }

    private func makeVaultNoteCard(_ file: VaultFile, origin: CGPoint, size: CGSize) -> CanvasCard {
        CanvasCard(
            id: UUID().uuidString,
            kind: .note,
            x: origin.x,
            y: origin.y,
            width: size.width,
            height: size.height,
            content: noteCardContent(for: file),
            title: vaultDisplayName(for: file),
            createdAt: Date()
        )
    }

    private func noteCardContent(for file: VaultFile) -> String {
        if file.kind == .note {
            if let content = file.noteContent, !content.isEmpty {
                return content
            }
            if let vaultURL,
               let content = VaultFilesystem.readNoteContent(relativePath: file.relativePath, vaultURL: vaultURL),
               !content.isEmpty {
                return content
            }
        }
        return "# \(vaultDisplayName(for: file))\n"
    }

    private func vaultDisplayName(for file: VaultFile) -> String {
        let baseName = (file.relativePath as NSString).lastPathComponent
        return (baseName as NSString).deletingPathExtension
    }

    private struct EndpointCardPlacement {
        let origin: CGPoint
        let toSide: CanvasSide
        let width: CGFloat
        let height: CGFloat

        var size: CGSize { CGSize(width: width, height: height) }
    }

    private func endpointCardPlacement(for edgeID: String, menuCenter: CGPoint) -> EndpointCardPlacement? {
        guard let edge = edges.first(where: { $0.id == edgeID }),
              let tip = edge.toPoint,
              let from = cards.first(where: { $0.id == edge.fromID }) else { return nil }

        let width = CanvasConstants.compactNoteWidth
        let height = CanvasConstants.compactNoteHeight
        let sourceAnchor = CanvasGeometry.anchor(for: from, side: edge.fromSide, overrides: [:], resizeOverrides: [:])
        let placed = CanvasGeometry.endpointCardPlacement(
            sourceAnchor: sourceAnchor,
            arrowTip: tip,
            menuCenter: menuCenter,
            cardWidth: width,
            cardHeight: height
        )
        return EndpointCardPlacement(origin: placed.origin, toSide: placed.connectingSide, width: width, height: height)
    }

    /// Dismisses the floating "Add card" menu and removes its dangling edge if still unlinked.
    func dismissPendingEndpoint() {
        pendingEndpointEdgeID = nil
        pendingEndpointMenuCenter = nil
        var removedEdge = false
        if case .endpoint(let edgeID, _, _) = contextMenu?.kind {
            withUndo {
                let before = edges.count
                edges.removeAll { $0.id == edgeID && $0.toID == nil }
                removedEdge = edges.count != before
            }
        }
        contextMenu = nil
        if removedEdge { notifyMutated() }
    }

    var filteredVaultFiles: [VaultFile] {
        let query = vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return vaultFiles }
        return vaultFiles.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.relativePath.localizedCaseInsensitiveContains(query)
        }
    }
}
