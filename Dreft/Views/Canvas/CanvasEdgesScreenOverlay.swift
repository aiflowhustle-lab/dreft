import SwiftUI

/// Draws connection lines in **screen space** above the transformed canvas — never clipped by cards or world bounds.
struct CanvasEdgesScreenOverlay: View {
    let transform: CanvasViewTransform
    let cardIndex: [String: CanvasCard]
    let edges: [CanvasEdge]
    let connectingFrom: (cardID: String, side: CanvasSide, toX: CGFloat, toY: CGFloat)?
    let positionOverrides: [String: CGPoint]
    let resizeOverrides: [String: CGRect]

    var body: some View {
        Canvas { context, _ in
            let lineScale = edgeLineScreenScale(for: transform.zoom)
            let glowW: CGFloat = 14 * lineScale
            let bodyW: CGFloat = 6.5 * lineScale
            let coreW: CGFloat = 3.2 * lineScale
            let arrowSize = CanvasConstants.edgeArrowScreenSize * lineScale
            let zoom = max(transform.zoom, 0.08)

            let glowColor = GraphicsContext.Shading.color(AppColors.edgeOuter)
            let bodyColor = GraphicsContext.Shading.color(AppColors.edgeStroke)
            let coreColor = GraphicsContext.Shading.color(AppColors.edgeHighlight)

            func toScreen(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: point.x * transform.zoom + transform.x,
                    y: point.y * transform.zoom + transform.y
                )
            }

            func drawTube(_ path: Path, cap: CGLineCap) {
                let style = { (width: CGFloat) in
                    StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: .round)
                }
                context.stroke(path, with: glowColor, style: style(glowW))
                context.stroke(path, with: bodyColor, style: style(bodyW))
                context.stroke(path, with: coreColor, style: style(coreW))
            }

            func drawArrowHead(at tip: CGPoint, toward origin: CGPoint) {
                let body = CanvasGeometry.arrowHead(at: tip, toward: origin, size: arrowSize)
                let glow = CanvasGeometry.arrowHead(at: tip, toward: origin, size: arrowSize + 3)
                context.fill(glow, with: glowColor)
                context.fill(body, with: bodyColor)
            }

            func drawEdge(from p1: CGPoint, fromSide: CanvasSide, to p2: CGPoint, toSide: CanvasSide?, showsArrow: Bool) {
                let worldPath = CanvasGeometry.bezierPath(from: p1, fromSide: fromSide, to: p2, toSide: toSide)

                if showsArrow {
                    let worldArrow = arrowSize / zoom
                    let tEnd = CanvasGeometry.trimTBeforeTip(
                        from: p1,
                        fromSide: fromSide,
                        to: p2,
                        toSide: toSide,
                        distance: worldArrow
                    )
                    let trimmed = worldPath.trimmedPath(from: 0, to: min(tEnd, 0.998))
                    let linePath = transformPath(trimmed, toScreen: toScreen)
                    drawTube(linePath, cap: .butt)

                    let tip = toScreen(p2)
                    let nearTip = toScreen(
                        CanvasGeometry.pointOnCurve(
                            from: p1,
                            fromSide: fromSide,
                            to: p2,
                            toSide: toSide,
                            t: max(tEnd - 0.05, 0)
                        )
                    )
                    drawArrowHead(at: tip, toward: nearTip)
                } else {
                    drawTube(transformPath(worldPath, toScreen: toScreen), cap: .round)
                }
            }

            for edge in edges {
                guard let from = cardIndex[edge.fromID] else { continue }
                let p1 = CanvasGeometry.anchor(for: from, side: edge.fromSide, overrides: positionOverrides, resizeOverrides: resizeOverrides)

                if let toID = edge.toID, let to = cardIndex[toID] {
                    let side = edge.toSide ?? .left
                    drawEdge(
                        from: p1,
                        fromSide: edge.fromSide,
                        to: CanvasGeometry.anchor(for: to, side: side, overrides: positionOverrides, resizeOverrides: resizeOverrides),
                        toSide: side,
                        showsArrow: true
                    )
                } else if let point = edge.toPoint {
                    drawEdge(from: p1, fromSide: edge.fromSide, to: point, toSide: nil, showsArrow: true)
                }
            }

            if let connecting = connectingFrom, let from = cardIndex[connecting.cardID] {
                let p1 = CanvasGeometry.anchor(for: from, side: connecting.side, overrides: positionOverrides, resizeOverrides: resizeOverrides)
                drawEdge(
                    from: p1,
                    fromSide: connecting.side,
                    to: CGPoint(x: connecting.toX, y: connecting.toY),
                    toSide: nil,
                    showsArrow: true
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// Thin lines when zoomed out; full weight at 100% zoom and above.
    private func edgeLineScreenScale(for zoom: CGFloat) -> CGFloat {
        min(1, max(0.22, zoom))
    }

  /// Sample Bézier world path into screen space.
  private func transformPath(_ path: Path, toScreen: (CGPoint) -> CGPoint) -> Path {
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
}
