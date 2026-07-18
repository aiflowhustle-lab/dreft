import Foundation

/// Chronological events for graph timelapse playback.
enum GraphTimelapseEvent: Equatable {
    case node(id: String, at: Date)
    case link(fromID: String, toID: String, at: Date)

    var timestamp: Date {
        switch self {
        case .node(_, let at), .link(_, _, let at):
            return at
        }
    }

    var sortKey: String {
        switch self {
        case .node(let id, let at):
            return "\(at.timeIntervalSince1970)-n-\(id)"
        case .link(let fromID, let toID, let at):
            return "\(at.timeIntervalSince1970)-l-\(fromID)-\(toID)"
        }
    }
}

struct GraphTimelapseTimeline: Equatable {
    var events: [GraphTimelapseEvent]
    var start: Date
    var end: Date

    var isEmpty: Bool { events.isEmpty }

    /// Delay between events — faster for large vaults, slower for small ones.
    var stepDelayMs: Int {
        let count = events.count
        if count <= 12 { return 420 }
        if count <= 40 { return 280 }
        if count <= 120 { return 180 }
        return 120
    }

    static func build(
        files: [WorkspaceFileEntry],
        edges: [GraphEdge],
        scopeIDs: Set<String>
    ) -> GraphTimelapseTimeline {
        let scopedFiles = files.filter {
            scopeIDs.contains($0.id) && ($0.kind == .note || $0.kind == .canvas)
        }
        guard !scopedFiles.isEmpty else {
            return GraphTimelapseTimeline(events: [], start: .distantPast, end: .distantPast)
        }

        let filesByID = Dictionary(uniqueKeysWithValues: scopedFiles.map { ($0.id, $0) })
        var events: [GraphTimelapseEvent] = []

        for file in scopedFiles {
            let appearance = file.createdAt
            events.append(.node(id: file.id, at: appearance))
        }

        for edge in edges {
            guard scopeIDs.contains(edge.fromID), scopeIDs.contains(edge.toID),
                  let from = filesByID[edge.fromID],
                  let to = filesByID[edge.toID] else { continue }
            // Link appears once both notes exist and the source was edited to include it.
            let linkDate = max(from.modifiedAt, from.createdAt, to.createdAt)
            events.append(.link(fromID: edge.fromID, toID: edge.toID, at: linkDate))
        }

        events.sort {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            return $0.sortKey < $1.sortKey
        }

        let start = events.first?.timestamp ?? Date()
        let end = events.last?.timestamp ?? start
        return GraphTimelapseTimeline(events: events, start: start, end: end)
    }
}
