import SwiftUI

/// Invisible wide strokes along connection lines — hit-testing above cards for hover, hand cursor, and drag.
struct CanvasEdgeHitOverlay: View {
    let transform: CanvasViewTransform
    let cardIndex: [String: CanvasCard]
    let edges: [CanvasEdge]
    let positionOverrides: [String: CGPoint]
    let resizeOverrides: [String: CGRect]
    var edgeEndpoint: (CanvasEdge) -> (point: CGPoint, toSide: CanvasSide?)?
    var onHoverEdge: (String?) -> Void

    private var hitWidth: CGFloat {
        max(16, min(28, 18 / max(transform.zoom, 0.25)))
    }

    var body: some View {
        ZStack {
            ForEach(edges) { edge in
                if let path = screenPath(for: edge) {
                    let hitShape = path.strokedPath(
                        StrokeStyle(lineWidth: hitWidth, lineCap: .round, lineJoin: .round)
                    )
                    hitShape
                        .fill(Color.clear)
                        .contentShape(hitShape)
                        #if os(macOS)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active:
                                Task { @MainActor in
                                    onHoverEdge(edge.id)
                                }
                            case .ended:
                                Task { @MainActor in
                                    onHoverEdge(nil)
                                }
                            }
                        }
                        #endif
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    private func screenPath(for edge: CanvasEdge) -> Path? {
        guard let from = cardIndex[edge.fromID],
              let endpoint = edgeEndpoint(edge) else { return nil }

        let p1 = CanvasGeometry.anchor(
            for: from,
            side: edge.fromSide,
            overrides: positionOverrides,
            resizeOverrides: resizeOverrides
        )
        let worldPath = CanvasGeometry.bezierPath(
            from: p1,
            fromSide: edge.fromSide,
            to: endpoint.point,
            toSide: endpoint.toSide
        )
        return transformPath(worldPath)
    }

    private func transformPath(_ path: Path) -> Path {
        var result = Path()
        path.forEach { element in
            switch element {
            case .move(let p):
                result.move(to: toScreen(p))
            case .line(let p):
                result.addLine(to: toScreen(p))
            case .quadCurve(let p, let c):
                result.addQuadCurve(to: toScreen(p), control: toScreen(c))
            case .curve(let p, let c1, let c2):
                result.addCurve(to: toScreen(p), control1: toScreen(c1), control2: toScreen(c2))
            case .closeSubpath:
                result.closeSubpath()
            }
        }
        return result
    }

    private func toScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * transform.zoom + transform.x,
            y: point.y * transform.zoom + transform.y
        )
    }
}
