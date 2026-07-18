import Foundation

enum CanvasDocumentReadOutcome {
    case success(CanvasDocumentSnapshot)
    case unsupportedVersion(Int)
    case invalid
}

/// On-disk `.canvas` JSON envelope with versioned migration.
enum CanvasDocumentFormat {
    /// Bump when the on-disk schema changes and add a migration step in `migrate`.
    static let currentVersion = 2

    private struct OnDiskCanvasDocument: Codable {
        var version: Int?
        var cards: [CanvasCard]
        var edges: [CanvasEdge]
        var transform: CanvasViewTransform
    }

    static func read(from data: Data) -> CanvasDocumentReadOutcome {
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(OnDiskCanvasDocument.self, from: data) {
            let version = document.version ?? 0
            guard let snapshot = migrate(document: document, from: version) else {
                if version > currentVersion {
                    return .unsupportedVersion(version)
                }
                return .invalid
            }
            return .success(snapshot)
        }
        if let snapshot = readJSONCanvas(from: data) {
            return .success(snapshot)
        }
        return .invalid
    }

    static func encode(_ snapshot: CanvasDocumentSnapshot) throws -> Data {
        let document = OnDiskCanvasDocument(
            version: currentVersion,
            cards: snapshot.cards,
            edges: snapshot.edges,
            transform: snapshot.transform
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func isDefaultSnapshot(_ snapshot: CanvasDocumentSnapshot) -> Bool {
        snapshot.cards.isEmpty
            && snapshot.edges.isEmpty
            && snapshot.transform == CanvasViewTransform()
    }

    /// Avoid clobbering unreadable on-disk canvases with an empty in-memory placeholder.
    static func shouldOverwriteExistingFile(at url: URL, with snapshot: CanvasDocumentSnapshot) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return true
        }
        switch read(from: data) {
        case .success:
            return true
        case .unsupportedVersion:
            return false
        case .invalid:
            return !snapshot.cards.isEmpty || !snapshot.edges.isEmpty
        }
    }

    private static func migrate(document: OnDiskCanvasDocument, from version: Int) -> CanvasDocumentSnapshot? {
        switch version {
        case 0, 1, 2:
            return CanvasDocumentSnapshot(
                cards: document.cards,
                edges: document.edges,
                transform: document.transform
            )
        default:
            return nil
        }
    }

    /// Obsidian / JSON Canvas (https://jsoncanvas.org) uses `nodes` + `fromNode`/`toNode` edges.
    private static func readJSONCanvas(from data: Data) -> CanvasDocumentSnapshot? {
        struct JSONCanvasNode: Decodable {
            let id: String
            let type: String
            let x: CGFloat
            let y: CGFloat
            let width: CGFloat
            let height: CGFloat
            let text: String?
            let file: String?
            let url: String?
            let label: String?
            let color: String?
        }

        struct JSONCanvasEdge: Decodable {
            let id: String
            let fromNode: String
            let fromSide: CanvasSide?
            let toNode: String
            let toSide: CanvasSide?
            let fromEnd: String?
            let toEnd: String?
            let label: String?
            let color: String?
        }

        struct JSONCanvasDocument: Decodable {
            let nodes: [JSONCanvasNode]?
            let edges: [JSONCanvasEdge]?
        }

        guard let document = try? JSONDecoder().decode(JSONCanvasDocument.self, from: data),
              document.nodes != nil || document.edges != nil else {
            return nil
        }

        var cards: [CanvasCard] = []
        cards.reserveCapacity(document.nodes?.count ?? 0)

        for node in document.nodes ?? [] {
            let colorHex = node.color?.hasPrefix("#") == true ? node.color : nil
            switch node.type {
            case "text":
                cards.append(
                    CanvasCard(
                        id: node.id,
                        kind: .text,
                        x: node.x,
                        y: node.y,
                        width: node.width,
                        height: node.height,
                        content: node.text ?? "",
                        colorHex: colorHex
                    )
                )
            case "file":
                let path = node.file ?? ""
                let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                cards.append(
                    CanvasCard(
                        id: node.id,
                        kind: .note,
                        x: node.x,
                        y: node.y,
                        width: node.width,
                        height: node.height,
                        content: path,
                        title: title.isEmpty ? nil : title,
                        colorHex: colorHex
                    )
                )
            case "link":
                cards.append(
                    CanvasCard(
                        id: node.id,
                        kind: .text,
                        x: node.x,
                        y: node.y,
                        width: node.width,
                        height: node.height,
                        content: node.url ?? "",
                        colorHex: colorHex
                    )
                )
            case "group":
                let label = node.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !label.isEmpty else { continue }
                cards.append(
                    CanvasCard(
                        id: node.id,
                        kind: .text,
                        x: node.x,
                        y: node.y,
                        width: node.width,
                        height: node.height,
                        content: label,
                        colorHex: colorHex
                    )
                )
            default:
                continue
            }
        }

        let cardIDs = Set(cards.map(\.id))
        var edges: [CanvasEdge] = []
        edges.reserveCapacity(document.edges?.count ?? 0)

        for edge in document.edges ?? [] {
            guard cardIDs.contains(edge.fromNode), cardIDs.contains(edge.toNode) else { continue }
            var mapped = CanvasEdge(
                fromID: edge.fromNode,
                fromSide: edge.fromSide ?? .right,
                toID: edge.toNode,
                toSide: edge.toSide ?? .left,
                direction: .fromObsidian(fromEnd: edge.fromEnd, toEnd: edge.toEnd),
                label: edge.label,
                colorHex: obsidianEdgeColorHex(edge.color)
            )
            mapped.id = edge.id
            edges.append(mapped)
        }

        return CanvasDocumentSnapshot(
            cards: cards,
            edges: edges,
            transform: CanvasViewTransform()
        )
    }

    /// JSON Canvas preset color ids → hex (Obsidian palette).
    private static func obsidianEdgeColorHex(_ preset: String?) -> String? {
        switch preset {
        case "1": return "#FB464C"
        case "2": return "#E9973F"
        case "3": return "#E0DE71"
        case "4": return "#44CF6E"
        case "5": return "#53DFDD"
        case "6": return "#A882FF"
        default:
            if let preset, preset.hasPrefix("#") { return preset }
            return nil
        }
    }
}
