import CoreGraphics
import Foundation
import SwiftUI

struct GraphLayoutGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var query: String
    var colorHex: String
}

private struct GraphLayoutDocument: Codable {
    var version: Int = 1
    var positions: [String: GraphLayoutPoint] = [:]
    var groups: [GraphLayoutGroup] = []
}

private struct GraphLayoutPoint: Codable {
    var x: Double
    var y: Double
}

struct GraphLayoutState {
    var positions: [String: CGPoint] = [:]
    var groups: [GraphLayoutGroup] = []
}

/// Persists graph node positions and group filters per vault at `.dreft/graph-layout.json`.
enum GraphLayoutPersistence {
    static let relativePath = ".dreft/graph-layout.json"

    static func load(vaultURL: URL) -> GraphLayoutState {
        let url = vaultURL.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(GraphLayoutDocument.self, from: data) else {
            return GraphLayoutState()
        }
        let positions = document.positions.mapValues { point in
            CGPoint(x: point.x, y: point.y)
        }
        return GraphLayoutState(positions: positions, groups: document.groups)
    }

    static func save(_ state: GraphLayoutState, vaultURL: URL) {
        let url = vaultURL.appendingPathComponent(relativePath)
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let document = GraphLayoutDocument(
            positions: state.positions.mapValues { point in
                GraphLayoutPoint(x: Double(point.x), y: Double(point.y))
            },
            groups: state.groups
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(document) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
