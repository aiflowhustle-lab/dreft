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
    var createdAt: Date?

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
            content: size.2,
            createdAt: Date()
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
            content: "",
            createdAt: Date()
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

enum CanvasEdgeDirection: String, Codable, CaseIterable, Identifiable {
    case nondirectional
    case unidirectional
    case bidirectional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nondirectional: "Nondirectional"
        case .unidirectional: "Unidirectional"
        case .bidirectional: "Bidirectional"
        }
    }

    var iconName: String {
        switch self {
        case .nondirectional: "minus"
        case .unidirectional: "arrow.right"
        case .bidirectional: "arrow.left.and.right"
        }
    }

    var showsFromArrow: Bool { self == .bidirectional }
    var showsToArrow: Bool { self == .unidirectional || self == .bidirectional }

    static func fromObsidian(fromEnd: String?, toEnd: String?) -> CanvasEdgeDirection {
        let fromArrow = fromEnd == "arrow"
        let toArrow = toEnd == nil || toEnd == "arrow"
        if fromArrow && toArrow { return .bidirectional }
        if !fromArrow && !toArrow { return .nondirectional }
        return .unidirectional
    }
}

struct CanvasEdge: Identifiable, Codable, Equatable {
    var id: String
    var fromID: String
    var fromSide: CanvasSide
    var toID: String?
    var toSide: CanvasSide?
    var toPoint: CGPoint?
    var direction: CanvasEdgeDirection
    var label: String?
    var colorHex: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, fromID, fromSide, toID, toSide, toPoint, direction, label, colorHex, createdAt
    }

    init(
        fromID: String,
        fromSide: CanvasSide,
        toID: String? = nil,
        toSide: CanvasSide? = nil,
        toPoint: CGPoint? = nil,
        direction: CanvasEdgeDirection = .unidirectional,
        label: String? = nil,
        colorHex: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = UUID().uuidString
        self.fromID = fromID
        self.fromSide = fromSide
        self.toID = toID
        self.toSide = toSide
        self.toPoint = toPoint
        self.direction = direction
        self.label = label
        self.colorHex = colorHex
        self.createdAt = createdAt ?? Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        fromID = try container.decode(String.self, forKey: .fromID)
        fromSide = try container.decode(CanvasSide.self, forKey: .fromSide)
        toID = try container.decodeIfPresent(String.self, forKey: .toID)
        toSide = try container.decodeIfPresent(CanvasSide.self, forKey: .toSide)
        toPoint = try container.decodeIfPresent(CGPoint.self, forKey: .toPoint)
        direction = try container.decodeIfPresent(CanvasEdgeDirection.self, forKey: .direction) ?? .unidirectional
        label = try container.decodeIfPresent(String.self, forKey: .label)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fromID, forKey: .fromID)
        try container.encode(fromSide, forKey: .fromSide)
        try container.encodeIfPresent(toID, forKey: .toID)
        try container.encodeIfPresent(toSide, forKey: .toSide)
        try container.encodeIfPresent(toPoint, forKey: .toPoint)
        try container.encode(direction, forKey: .direction)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(colorHex, forKey: .colorHex)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
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
    /// Extra world padding while panning/pinching — keeps nearby cards mounted without rendering the whole canvas.
    static let interactionViewportPadding: CGFloat = 480
    /// Extra padding beyond the interaction buffer for background image prefetch.
    static let prefetchViewportPadding: CGFloat = 320
    /// Debounce before expanding the mounted card set while panning/zooming.
    static let cullingDebounceMs: Int = 100
    /// LRU cap for decoded canvas image thumbnails.
    static let imageCacheMaxEntries: Int = 96
    static let imageCacheMaxBytes: Int = 96 * 1024 * 1024
    /// Zoom below this: colored rectangles only (Tier 2 LOD).
    static let lodBlockZoomThreshold: CGFloat = 0.25
    /// Fixed screen-pixel arrow size — stays visually consistent when zooming.
    static let edgeArrowScreenSize: CGFloat = 13
    /// Default compact note size (image-card connection / canvas click).
    static let compactNoteWidth: CGFloat = 180
    static let compactNoteHeight: CGFloat = 56
    /// Default dangling connector length when clicking a handle without dragging.
    static let defaultConnectDistance: CGFloat = 150
}

/// Render detail for **note** cards when zoomed out. Image cards always stay full fidelity (Obsidian-style).
enum CanvasCardLOD: Int, Comparable {
    case block
    case summary
    case full

    static func < (lhs: CanvasCardLOD, rhs: CanvasCardLOD) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func resolve(
        zoom: CGFloat,
        isSelected: Bool,
        isLinkTarget: Bool,
        isEditing: Bool
    ) -> CanvasCardLOD {
        if isSelected || isLinkTarget || isEditing { return .full }
        if zoom < CanvasConstants.lodBlockZoomThreshold { return .block }
        return .full
    }
}
