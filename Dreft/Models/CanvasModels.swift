import CoreGraphics
import Foundation

enum CardKind: String, Codable, CaseIterable {
    case note
    case text
    case image
}

enum CanvasSide: String, Codable, CaseIterable {
    case top, right, bottom, left

    var opposite: CanvasSide {
        switch self {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }

    func normal(dx: CGFloat, dy: CGFloat) -> CGPoint {
        switch self {
        case .right: CGPoint(x: 1, y: 0)
        case .left: CGPoint(x: -1, y: 0)
        case .top: CGPoint(x: 0, y: -1)
        case .bottom: CGPoint(x: 0, y: 1)
        }
    }
}

struct CanvasCard: Identifiable, Codable, Equatable {
    var id: String
    var kind: CardKind
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var content: String
    var title: String?
    var colorHex: String?

    static func make(kind: CardKind, at center: CGPoint) -> CanvasCard {
        let size: (CGFloat, CGFloat, String) = switch kind {
        case .note: (260, 180, "")
        case .text: (220, 60, "Text")
        case .image: (260, 180, "")
        }
        return CanvasCard(
            id: UUID().uuidString,
            kind: kind,
            x: center.x - size.0 / 2,
            y: center.y - size.1 / 2,
            width: size.0,
            height: size.1,
            content: size.2
        )
    }

    /// Compact note — same size as notes created from image-card connections.
    static func makeCompactNote(at center: CGPoint) -> CanvasCard {
        CanvasCard(
            id: UUID().uuidString,
            kind: .note,
            x: center.x - CanvasConstants.compactNoteWidth / 2,
            y: center.y - CanvasConstants.compactNoteHeight / 2,
            width: CanvasConstants.compactNoteWidth,
            height: CanvasConstants.compactNoteHeight,
            content: ""
        )
    }

    func anchor(for side: CanvasSide) -> CGPoint {
        switch side {
        case .right: CGPoint(x: x + width, y: y + height / 2)
        case .left: CGPoint(x: x, y: y + height / 2)
        case .top: CGPoint(x: x + width / 2, y: y)
        case .bottom: CGPoint(x: x + width / 2, y: y + height)
        }
    }
}

struct CanvasEdge: Identifiable, Codable, Equatable {
    var id: String
    var fromID: String
    var fromSide: CanvasSide
    var toID: String?
    var toSide: CanvasSide?
    var toPoint: CGPoint?

    init(fromID: String, fromSide: CanvasSide, toID: String? = nil, toSide: CanvasSide? = nil, toPoint: CGPoint? = nil) {
        self.id = UUID().uuidString
        self.fromID = fromID
        self.fromSide = fromSide
        self.toID = toID
        self.toSide = toSide
        self.toPoint = toPoint
    }
}

struct CanvasViewTransform: Equatable, Codable {
    enum CodingKeys: String, CodingKey {
        case x, y, zoom
    }

    var x: CGFloat = 0
    var y: CGFloat = 0
    var zoom: CGFloat = 1

    static let minZoom: CGFloat = 0.05
    static let maxZoom: CGFloat = 3
}

enum CanvasConstants {
    static let worldSize: CGFloat = 8_192
    static let dotSpacing: CGFloat = 22
    static let dotSize: CGFloat = 3
    static let displayMaxImagePixelEdge: CGFloat = 1024
    static let viewportPadding: CGFloat = 160
    /// Fixed screen-pixel arrow size — stays visually consistent when zooming.
    static let edgeArrowScreenSize: CGFloat = 13
    /// Default compact note size (image-card connection / canvas click).
    static let compactNoteWidth: CGFloat = 180
    static let compactNoteHeight: CGFloat = 56
    /// Default dangling connector length when clicking a handle without dragging.
    static let defaultConnectDistance: CGFloat = 150
}
