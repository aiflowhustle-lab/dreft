import Foundation

enum CanvasTimelapseEvent: Equatable {
    case card(id: String, at: Date)
    case edge(id: String, at: Date)

    var timestamp: Date {
        switch self {
        case .card(_, let at), .edge(_, let at):
            return at
        }
    }

    var sortKey: String {
        switch self {
        case .card(let id, let at):
            return "\(at.timeIntervalSince1970)-c-\(id)"
        case .edge(let id, let at):
            return "\(at.timeIntervalSince1970)-e-\(id)"
        }
    }
}

struct CanvasTimelapseTimeline: Equatable {
    var events: [CanvasTimelapseEvent]
    var start: Date
    var end: Date

    var isEmpty: Bool { events.isEmpty }

    var stepDelayMs: Int {
        let count = events.count
        if count <= 12 { return 420 }
        if count <= 40 { return 280 }
        if count <= 120 { return 180 }
        return 120
    }

    static func build(
        cards: [CanvasCard],
        edges: [CanvasEdge],
        files: [WorkspaceFileEntry],
        vaultURL: URL?,
        canvasRelativePath: String?,
        canvasCreatedAt: Date?
    ) -> CanvasTimelapseTimeline {
        guard !cards.isEmpty else {
            return CanvasTimelapseTimeline(events: [], start: .distantPast, end: .distantPast)
        }

        let filesByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.relativePath, $0) })
        let fallbackBase = canvasCreatedAt
            ?? files.filter { $0.kind == .canvas }.map(\.createdAt).min()
            ?? files.map(\.createdAt).min()
            ?? Date(timeIntervalSince1970: 1_704_067_200)

        var cardDates = Dictionary(uniqueKeysWithValues: cards.compactMap { card in
            card.createdAt.map { (card.id, $0) }
        })
        var edgeDates = Dictionary(uniqueKeysWithValues: edges.compactMap { edge in
            edge.createdAt.map { (edge.id, $0) }
        })

        if let vaultURL, let canvasRelativePath {
            applyVersionHistoryDates(
                vaultURL: vaultURL,
                canvasRelativePath: canvasRelativePath,
                cardDates: &cardDates,
                edgeDates: &edgeDates
            )
        }

        for (index, card) in cards.enumerated() where cardDates[card.id] == nil {
            cardDates[card.id] = inferredCardDate(
                for: card,
                orderIndex: index,
                filesByPath: filesByPath,
                vaultURL: vaultURL,
                fallbackBase: fallbackBase
            )
        }

        for edge in edges where edgeDates[edge.id] == nil {
            edgeDates[edge.id] = inferredEdgeDate(
                for: edge,
                cardDates: cardDates
            )
        }

        var events: [CanvasTimelapseEvent] = []
        events.reserveCapacity(cards.count + edges.count)

        for card in cards {
            let at = cardDates[card.id] ?? fallbackBase
            events.append(.card(id: card.id, at: at))
        }

        for edge in edges {
            let at = edgeDates[edge.id] ?? fallbackBase
            events.append(.edge(id: edge.id, at: at))
        }

        events.sort {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            switch ($0, $1) {
            case (.edge, .card):
                return true
            case (.card, .edge):
                return false
            default:
                return $0.sortKey < $1.sortKey
            }
        }

        let start = events.first?.timestamp ?? Date()
        let end = events.last?.timestamp ?? start
        return CanvasTimelapseTimeline(events: events, start: start, end: end)
    }

    private static func applyVersionHistoryDates(
        vaultURL: URL,
        canvasRelativePath: String,
        cardDates: inout [String: Date],
        edgeDates: inout [String: Date]
    ) {
        for (date, snapshot) in loadHistoricalSnapshots(
            vaultURL: vaultURL,
            canvasRelativePath: canvasRelativePath
        ) {
            for card in snapshot.cards where cardDates[card.id] == nil {
                cardDates[card.id] = card.createdAt ?? date
            }
            for edge in snapshot.edges where edgeDates[edge.id] == nil {
                edgeDates[edge.id] = edge.createdAt ?? date
            }
        }
    }

    private static func loadHistoricalSnapshots(
        vaultURL: URL,
        canvasRelativePath: String
    ) -> [(Date, CanvasDocumentSnapshot)] {
        let fileManager = FileManager.default
        var snapshots: [(Date, CanvasDocumentSnapshot)] = []

        let versionsDirectory = VaultFilesystem.canvasVersionsDirectory(
            forRelativePath: canvasRelativePath,
            vaultURL: vaultURL
        )
        if let versionURLs = try? fileManager.contentsOfDirectory(
            at: versionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
        ) {
            for url in versionURLs where url.pathExtension == "canvas" {
                guard let snapshot = VaultFilesystem.readCanvas(at: url) else { continue }
                let date = fileTimestamp(for: url) ?? .distantPast
                snapshots.append((date, snapshot))
            }
        }

        let canvasURL = vaultURL.appendingPathComponent(canvasRelativePath)
        if fileManager.fileExists(atPath: canvasURL.path),
           let snapshot = VaultFilesystem.readCanvas(at: canvasURL) {
            let date = fileTimestamp(for: canvasURL) ?? Date()
            snapshots.append((date, snapshot))
        }

        return snapshots.sorted { $0.0 < $1.0 }
    }

    private static func fileTimestamp(for url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey
        ]) else { return nil }
        return values.contentModificationDate ?? values.creationDate
    }

    private static func inferredCardDate(
        for card: CanvasCard,
        orderIndex: Int,
        filesByPath: [String: WorkspaceFileEntry],
        vaultURL: URL?,
        fallbackBase: Date
    ) -> Date {
        if let path = CanvasCardContent.linkedNotePath(for: card),
           let file = filesByPath[path] {
            return file.createdAt
        }

        if card.kind == .image {
            let trimmed = card.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !VaultFilesystem.isEmbeddedImageContent(trimmed) {
                if let file = filesByPath[trimmed] {
                    return file.createdAt
                }
                if let vaultURL, let assetDate = fileTimestamp(for: vaultURL.appendingPathComponent(trimmed)) {
                    return assetDate
                }
            }
        }

        return fallbackBase.addingTimeInterval(TimeInterval(orderIndex) * 45)
    }

    /// Edges pulled from a card appear before the card/image placed at the endpoint.
    private static func inferredEdgeDate(
        for edge: CanvasEdge,
        cardDates: [String: Date]
    ) -> Date? {
        guard let fromDate = cardDates[edge.fromID] else { return nil }

        if edge.toPoint != nil, edge.toID == nil {
            return fromDate.addingTimeInterval(2)
        }

        guard let toID = edge.toID, let toDate = cardDates[toID] else {
            return fromDate.addingTimeInterval(2)
        }

        let gap = toDate.timeIntervalSince(fromDate)
        if gap > 30 {
            // Typical pull-line flow: line first, destination card/image later.
            return fromDate.addingTimeInterval(2)
        }

        return max(fromDate, toDate).addingTimeInterval(1)
    }
}
