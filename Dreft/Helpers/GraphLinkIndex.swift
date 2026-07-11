import Foundation

struct GraphEdge: Hashable, Sendable {
    let fromID: String
    let toID: String

    var key: String { "\(fromID)->\(toID)" }
}

/// Cached wikilink graph with O(1) target resolution and incremental note updates.
final class GraphLinkIndex: @unchecked Sendable {
    private(set) var edges: [GraphEdge] = []

    private var edgeKeys: Set<String> = []
    private var outgoingBySource: [String: [GraphEdge]] = [:]
    private var incomingByTarget: [String: [GraphEdge]] = [:]
    private var noteCacheEntries: [String: NoteLinkCacheEntry] = [:]

    private var pathToID: [String: String] = [:]
    private var pathStemToID: [String: String] = [:]
    private var normalizedNameToIDs: [String: Set<String>] = [:]
    private var fileByID: [String: WorkspaceFileEntry] = [:]
    private var noteIDs: [String] = []

    func cacheSnapshot() -> GraphLinkIndexCache {
        GraphLinkIndexCache(version: 1, notes: noteCacheEntries)
    }

    /// Full rebuild — used when no cache is available.
    func rebuild(from files: [WorkspaceFileEntry], vaultURL: URL? = nil) {
        _ = sync(from: files, vaultURL: vaultURL, cache: nil)
    }

    /// Rebuilds lookup tables and re-parses only notes whose modification time changed.
    @discardableResult
    func sync(
        from files: [WorkspaceFileEntry],
        vaultURL: URL?,
        cache: GraphLinkIndexCache?
    ) -> GraphLinkIndexCache {
        rebuildLookup(from: files)

        var nextEdges: [GraphEdge] = []
        var nextEdgeKeys: Set<String> = []
        var nextOutgoing: [String: [GraphEdge]] = [:]
        var nextIncoming: [String: [GraphEdge]] = [:]
        var nextCacheEntries: [String: NoteLinkCacheEntry] = [:]

        for id in noteIDs {
            guard let file = fileByID[id] else { continue }
            let modifiedAt = file.modifiedAt.timeIntervalSince1970

            if let cached = cache?.notes[id], timestampsMatch(cached.modifiedAt, modifiedAt) {
                let targets = appendCachedOutgoing(
                    fromID: id,
                    toIDs: cached.outgoingToIDs,
                    edges: &nextEdges,
                    edgeKeys: &nextEdgeKeys,
                    outgoing: &nextOutgoing,
                    incoming: &nextIncoming
                )
                nextCacheEntries[id] = NoteLinkCacheEntry(modifiedAt: modifiedAt, outgoingToIDs: targets)
            } else {
                let content = content(for: file, vaultURL: vaultURL)
                let targets = appendParsedOutgoing(
                    fromID: id,
                    content: content,
                    edges: &nextEdges,
                    edgeKeys: &nextEdgeKeys,
                    outgoing: &nextOutgoing,
                    incoming: &nextIncoming
                )
                nextCacheEntries[id] = NoteLinkCacheEntry(modifiedAt: modifiedAt, outgoingToIDs: targets)
            }
        }

        edges = nextEdges
        edgeKeys = nextEdgeKeys
        outgoingBySource = nextOutgoing
        incomingByTarget = nextIncoming
        noteCacheEntries = nextCacheEntries

        return cacheSnapshot()
    }

    func rebuildLookup(from files: [WorkspaceFileEntry]) {
        pathToID.removeAll(keepingCapacity: true)
        pathStemToID.removeAll(keepingCapacity: true)
        normalizedNameToIDs.removeAll(keepingCapacity: true)
        fileByID.removeAll(keepingCapacity: true)
        noteIDs.removeAll(keepingCapacity: true)

        for file in files where file.kind == .note || file.kind == .canvas {
            fileByID[file.id] = file
            let pathKey = file.relativePath.lowercased()
            pathToID[pathKey] = file.id

            let stem = (file.relativePath as NSString).deletingPathExtension
            pathStemToID[stem.lowercased()] = file.id

            normalizedNameToIDs[WikilinkParser.normalizedName(file.name), default: []].insert(file.id)
            normalizedNameToIDs[WikilinkParser.normalizedName(stem), default: []].insert(file.id)

            if file.kind == .note {
                noteIDs.append(file.id)
            }
        }
    }

    /// Re-parse outgoing links for one note after an in-memory edit.
    func updateNoteContent(id: String, content: String, modifiedAt: Date) {
        removeOutgoing(from: id)
        let targets = ingestNoteReturningTargets(id: id, content: content)
        noteCacheEntries[id] = NoteLinkCacheEntry(
            modifiedAt: modifiedAt.timeIntervalSince1970,
            outgoingToIDs: targets
        )
    }

    /// Drop all edges involving a removed file id.
    func removeFile(id: String) {
        removeOutgoing(from: id)
        if let incoming = incomingByTarget[id] {
            for edge in incoming {
                edgeKeys.remove(edge.key)
                outgoingBySource[edge.fromID]?.removeAll { $0.key == edge.key }
            }
        }
        edges.removeAll { $0.toID == id }
        edgeKeys = Set(edges.map(\.key))
        incomingByTarget.removeValue(forKey: id)
        noteCacheEntries.removeValue(forKey: id)
        rebuildAdjacencyIndices()
    }

    /// Notes and canvases within `depth` hops of `centerID` (both link directions).
    func neighborhood(around centerID: String, depth: Int) -> Set<String> {
        guard depth >= 0 else { return [centerID] }

        var visited: Set<String> = [centerID]
        var frontier: Set<String> = [centerID]

        for _ in 0..<depth {
            var next: Set<String> = []
            for id in frontier {
                for neighbor in outgoingLinkIDs(for: id) + incomingLinkIDs(for: id) {
                    if visited.insert(neighbor).inserted {
                        next.insert(neighbor)
                    }
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }

        return visited
    }

    func incomingCount(for fileID: String) -> Int {
        incomingByTarget[fileID]?.count ?? 0
    }

    func incomingLinkIDs(for fileID: String) -> [String] {
        incomingByTarget[fileID]?.map(\.fromID) ?? []
    }

    func outgoingLinkIDs(for fileID: String) -> [String] {
        outgoingBySource[fileID]?.map(\.toID) ?? []
    }

    // MARK: - Private

    private func timestampsMatch(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    @discardableResult
    private func appendCachedOutgoing(
        fromID: String,
        toIDs: [String],
        edges: inout [GraphEdge],
        edgeKeys: inout Set<String>,
        outgoing: inout [String: [GraphEdge]],
        incoming: inout [String: [GraphEdge]]
    ) -> [String] {
        var validTargets: [String] = []
        for toID in toIDs {
            guard fileByID[toID] != nil, toID != fromID else { continue }
            appendEdge(
                fromID: fromID,
                toID: toID,
                edges: &edges,
                edgeKeys: &edgeKeys,
                outgoing: &outgoing,
                incoming: &incoming
            )
            validTargets.append(toID)
        }
        return validTargets
    }

    @discardableResult
    private func appendParsedOutgoing(
        fromID: String,
        content: String,
        edges: inout [GraphEdge],
        edgeKeys: inout Set<String>,
        outgoing: inout [String: [GraphEdge]],
        incoming: inout [String: [GraphEdge]]
    ) -> [String] {
        var validTargets: [String] = []
        for target in WikilinkParser.linkTargets(in: content) {
            guard let toID = resolveTarget(target), toID != fromID else { continue }
            appendEdge(
                fromID: fromID,
                toID: toID,
                edges: &edges,
                edgeKeys: &edgeKeys,
                outgoing: &outgoing,
                incoming: &incoming
            )
            validTargets.append(toID)
        }
        return validTargets
    }

    @discardableResult
    private func ingestNoteReturningTargets(id: String, content: String) -> [String] {
        var validTargets: [String] = []
        for target in WikilinkParser.linkTargets(in: content) {
            guard let toID = resolveTarget(target), toID != id else { continue }
            appendEdge(fromID: id, toID: toID)
            validTargets.append(toID)
        }
        return validTargets
    }

    private func appendEdge(fromID: String, toID: String) {
        appendEdge(
            fromID: fromID,
            toID: toID,
            edges: &edges,
            edgeKeys: &edgeKeys,
            outgoing: &outgoingBySource,
            incoming: &incomingByTarget
        )
    }

    private func appendEdge(
        fromID: String,
        toID: String,
        edges: inout [GraphEdge],
        edgeKeys: inout Set<String>,
        outgoing: inout [String: [GraphEdge]],
        incoming: inout [String: [GraphEdge]]
    ) {
        let edge = GraphEdge(fromID: fromID, toID: toID)
        guard edgeKeys.insert(edge.key).inserted else { return }
        edges.append(edge)
        outgoing[fromID, default: []].append(edge)
        incoming[toID, default: []].append(edge)
    }

    private func removeOutgoing(from sourceID: String) {
        guard let outgoing = outgoingBySource[sourceID] else { return }
        for edge in outgoing {
            edgeKeys.remove(edge.key)
            if var incoming = incomingByTarget[edge.toID] {
                incoming.removeAll { $0.key == edge.key }
                if incoming.isEmpty {
                    incomingByTarget.removeValue(forKey: edge.toID)
                } else {
                    incomingByTarget[edge.toID] = incoming
                }
            }
        }
        edges.removeAll { $0.fromID == sourceID }
        outgoingBySource[sourceID] = []
    }

    private func rebuildAdjacencyIndices() {
        outgoingBySource.removeAll(keepingCapacity: true)
        incomingByTarget.removeAll(keepingCapacity: true)
        for edge in edges {
            outgoingBySource[edge.fromID, default: []].append(edge)
            incomingByTarget[edge.toID, default: []].append(edge)
        }
    }

    private func content(for file: WorkspaceFileEntry, vaultURL: URL?) -> String {
        if !file.noteContent.isEmpty { return file.noteContent }
        guard let vaultURL, file.kind == .note else { return "" }
        return VaultFilesystem.readNoteContent(relativePath: file.relativePath, vaultURL: vaultURL) ?? ""
    }

    private func resolveTarget(_ target: String) -> String? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if let id = pathToID[lower] { return id }

        let mdCandidate = lower.hasSuffix(".md") ? lower : "\(lower).md"
        if let id = pathToID[mdCandidate] { return id }

        let canvasCandidate = lower.hasSuffix(".canvas") ? lower : "\(lower).canvas"
        if let id = pathToID[canvasCandidate] { return id }

        if let id = pathStemToID[lower] { return id }

        let base = ((trimmed as NSString).lastPathComponent as NSString).deletingPathExtension
        let normalizedBase = WikilinkParser.normalizedName(base)
        var candidates = normalizedNameToIDs[normalizedBase] ?? []

        if candidates.isEmpty {
            for file in fileByID.values {
                if file.name.caseInsensitiveCompare(base) == .orderedSame
                    || (file.relativePath as NSString).lastPathComponent
                        .caseInsensitiveCompare((trimmed as NSString).lastPathComponent) == .orderedSame {
                    candidates.insert(file.id)
                }
            }
        }

        if candidates.count == 1 {
            return candidates.first
        }

        if trimmed.contains("/") {
            for id in candidates {
                if fileByID[id]?.relativePath.localizedCaseInsensitiveContains(trimmed) == true {
                    return id
                }
            }
        }

        return candidates.first
    }
}
