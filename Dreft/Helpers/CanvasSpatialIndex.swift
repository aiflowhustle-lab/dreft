import CoreGraphics
import Foundation

/// Uniform grid index for fast viewport queries on large canvases.
struct CanvasSpatialIndex {
    static let minimumCardCount = 30
    private static let cellSize: CGFloat = 384

    private struct CellKey: Hashable {
        let x: Int
        let y: Int
    }

    private var grid: [CellKey: [String]] = [:]
    private var boundsByID: [String: CGRect] = [:]

    init(cards: [CanvasCard]) {
        grid.reserveCapacity(max(cards.count / 4, 8))
        boundsByID.reserveCapacity(cards.count)

        for card in cards {
            let rect = CGRect(x: card.x, y: card.y, width: card.width, height: card.height)
            boundsByID[card.id] = rect
            for key in Self.cellKeys(for: rect) {
                grid[key, default: []].append(card.id)
            }
        }
    }

    /// Candidate card IDs whose indexed bounds overlap the viewport.
    func candidateIDs(intersecting viewport: CGRect) -> Set<String> {
        var ids = Set<String>()
        for key in Self.cellKeys(for: viewport) {
            guard let bucket = grid[key] else { continue }
            for id in bucket {
                guard let rect = boundsByID[id], rect.intersects(viewport) else { continue }
                ids.insert(id)
            }
        }
        return ids
    }

    private static func cellKeys(for rect: CGRect) -> [CellKey] {
        let minX = Int(floor(rect.minX / cellSize))
        let maxX = Int(floor(rect.maxX / cellSize))
        let minY = Int(floor(rect.minY / cellSize))
        let maxY = Int(floor(rect.maxY / cellSize))

        var keys: [CellKey] = []
        keys.reserveCapacity(max(1, (maxX - minX + 1) * (maxY - minY + 1)))
        for x in minX...maxX {
            for y in minY...maxY {
                keys.append(CellKey(x: x, y: y))
            }
        }
        return keys
    }
}
