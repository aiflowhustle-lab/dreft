import Foundation

struct NoteLinkCacheEntry: Codable, Hashable, Sendable {
    var modifiedAt: TimeInterval
    var outgoingToIDs: [String]
}

struct GraphLinkIndexCache: Codable, Sendable {
    var version: Int = 1
    var notes: [String: NoteLinkCacheEntry] = [:]
}

/// Persists parsed wikilink metadata per vault at `.dreft/link-index.json`.
enum GraphLinkIndexPersistence {
    static let relativePath = ".dreft/link-index.json"

    static func load(vaultURL: URL) -> GraphLinkIndexCache? {
        let url = vaultURL.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(GraphLinkIndexCache.self, from: data) else {
            return nil
        }
        return cache
    }

    static func save(_ cache: GraphLinkIndexCache, vaultURL: URL) {
        let url = vaultURL.appendingPathComponent(relativePath)
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
