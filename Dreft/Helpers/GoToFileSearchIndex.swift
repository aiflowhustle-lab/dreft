import Foundation

/// Fast prefix search index for the go-to-file quick switcher.
final class GoToFileSearchIndex {
    private struct Entry {
        let fileID: String
        let normalizedName: String
        let normalizedPath: String
    }

    private final class TrieNode {
        var children: [UnicodeScalar: TrieNode] = [:]
        var fileIDs: [String] = []
    }

    private var entries: [Entry] = []
    private var entriesByID: [String: Entry] = [:]
    private let root = TrieNode()
    private static let resultLimit = 250

    func rebuild(from files: [WorkspaceFileEntry]) {
        entries.removeAll(keepingCapacity: true)
        entriesByID.removeAll(keepingCapacity: true)
        clearTrie(root)

        entries.reserveCapacity(files.count)
        for file in files where file.kind != .folder && !file.relativePath.hasPrefix(".dreft/") {
            let entry = Entry(
                fileID: file.id,
                normalizedName: Self.normalize(file.name),
                normalizedPath: Self.normalize(file.relativePath)
            )
            entries.append(entry)
            entriesByID[file.id] = entry
            insert(entry.normalizedName, fileID: file.id)
        }

        entries.sort { $0.normalizedName.localizedStandardCompare($1.normalizedName) == .orderedAscending }
    }

    func search(_ query: String, files: [WorkspaceFileEntry]) -> [WorkspaceFileEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return materialize(entries.map(\.fileID), from: files, preserveOrder: true)
        }

        let normalizedQuery = Self.normalize(trimmed)
        var ranked: [(fileID: String, score: Int)] = []
        var seen = Set<String>()

        for fileID in prefixMatches(for: normalizedQuery) {
            guard seen.insert(fileID).inserted,
                  let entry = entriesByID[fileID] else { continue }
            ranked.append((fileID, score(entry: entry, query: normalizedQuery)))
        }

        if normalizedQuery.contains("/") {
            for entry in entries where entry.normalizedPath.contains(normalizedQuery) {
                guard seen.insert(entry.fileID).inserted else { continue }
                ranked.append((entry.fileID, 320))
            }
        } else if ranked.count < Self.resultLimit {
            for entry in entries {
                guard seen.insert(entry.fileID).inserted else { continue }
                let value = score(entry: entry, query: normalizedQuery)
                if value > 0 {
                    ranked.append((entry.fileID, value))
                }
            }
        }

        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let leftName = entriesByID[lhs.fileID]?.normalizedName ?? ""
            let rightName = entriesByID[rhs.fileID]?.normalizedName ?? ""
            return leftName.localizedStandardCompare(rightName) == .orderedAscending
        }

        let ids = ranked.prefix(Self.resultLimit).map(\.fileID)
        return materialize(Array(ids), from: files, preserveOrder: true)
    }

    // MARK: - Private

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func insert(_ key: String, fileID: String) {
        var node = root
        for scalar in key.unicodeScalars {
            let child = node.children[scalar] ?? TrieNode()
            node.children[scalar] = child
            node = child
            node.fileIDs.append(fileID)
        }
    }

    private func prefixMatches(for prefix: String) -> [String] {
        var node: TrieNode? = root
        for scalar in prefix.unicodeScalars {
            node = node?.children[scalar]
            guard node != nil else { return [] }
        }
        return node?.fileIDs ?? []
    }

    private func score(entry: Entry, query: String) -> Int {
        if entry.normalizedName == query { return 1_000 }
        if entry.normalizedName.hasPrefix(query) { return 850 - min(entry.normalizedName.count, 200) }
        if entry.normalizedName.contains(query) { return 520 }
        if entry.normalizedPath.contains(query) { return 300 }
        return 0
    }

    private func materialize(
        _ ids: [String],
        from files: [WorkspaceFileEntry],
        preserveOrder: Bool
    ) -> [WorkspaceFileEntry] {
        let fileMap = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        if preserveOrder {
            return ids.compactMap { fileMap[$0] }
        }
        return ids.compactMap { fileMap[$0] }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func clearTrie(_ node: TrieNode) {
        node.fileIDs.removeAll(keepingCapacity: true)
        for child in node.children.values {
            clearTrie(child)
        }
        node.children.removeAll(keepingCapacity: true)
    }
}
