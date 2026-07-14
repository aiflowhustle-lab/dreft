import SwiftUI

/// Draws connection lines in **screen space** above the transformed canvas — never clipped by cards or world bounds.
struct CanvasEdgesScreenOverlay: View {
    let transform: CanvasViewTransform
    let cardIndex: [String: CanvasCard]
    let edges: [CanvasEdge]
    let connectingFrom: (cardID: String, side: CanvasSide, toX: CGFloat, toY: CGFloat)?
    let positionOverrides: [String: CGPoint]
    let resizeOverrides: [String: CGRect]
    var selectedEdgeID: String?
    var editingEdgeID: String?
    var editingLabelDraft: String = ""

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
            let selectedGlow = GraphicsContext.Shading.color(AppColors.selectionStroke.opacity(0.35))
            let selectedBody = GraphicsContext.Shading.color(AppColors.selectionStroke)
            let selectedCore = GraphicsContext.Shading.color(AppColors.selectionStroke.opacity(0.9))

            func toScreen(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: point.x * transform.zoom + transform.x,
                    y: point.y * transform.zoom + transform.y
                )
            }

            func drawTube(_ path: Path, cap: CGLineCap, isSelected: Bool) {
                let style = { (width: CGFloat) in
                    StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: .round)
                }
                context.stroke(path, with: isSelected ? selectedGlow : glowColor, style: style(glowW))
                context.stroke(path, with: isSelected ? selectedBody : bodyColor, style: style(bodyW))
                context.stroke(path, with: isSelected ? selectedCore : coreColor, style: style(coreW))
            }

            func drawArrowHead(
                at tip: CGPoint,
                toward origin: CGPoint,
                stroke: (GraphicsContext.Shading, GraphicsContext.Shading, GraphicsContext.Shading)
            ) {
                let body = CanvasGeometry.arrowHead(at: tip, toward: origin, size: arrowSize)
                let glow = CanvasGeometry.arrowHead(at: tip, toward: origin, size: arrowSize + 3)
                context.fill(glow, with: stroke.0)
                context.fill(body, with: stroke.1)
            }

            func edgeStrokeSet(for edge: CanvasEdge, isSelected: Bool) -> (GraphicsContext.Shading, GraphicsContext.Shading, GraphicsContext.Shading) {
                if let custom = edgeStrokeColor(from: edge.colorHex) {
                    if isSelected {
                        return (
                            GraphicsContext.Shading.color(custom.opacity(0.35)),
                            GraphicsContext.Shading.color(custom),
                            GraphicsContext.Shading.color(custom.opacity(0.95))
                        )
                    }
                    return (
                        GraphicsContext.Shading.color(custom.opacity(0.28)),
                        GraphicsContext.Shading.color(custom),
                        GraphicsContext.Shading.color(custom.opacity(0.88))
                    )
                }
                if isSelected {
                    return (selectedGlow, selectedBody, selectedCore)
                }
                return (glowColor, bodyColor, coreColor)
            }

            func drawEdge(
                from p1: CGPoint,
                fromSide: CanvasSide,
                to p2: CGPoint,
                toSide: CanvasSide?,
                direction: CanvasEdgeDirection,
                isSelected: Bool = false,
                label: String? = nil,
                stroke: (GraphicsContext.Shading, GraphicsContext.Shading, GraphicsContext.Shading)? = nil
            ) {
                let strokeSet = stroke ?? (glowColor, bodyColor, coreColor)
                let worldPath = CanvasGeometry.bezierPath(from: p1, fromSide: fromSide, to: p2, toSide: toSide)
                let showsFrom = direction.showsFromArrow
                let showsTo = direction.showsToArrow
                let worldArrow = arrowSize / zoom

                var tStart: CGFloat = 0
                var tEnd: CGFloat = 1

                if showsTo {
                    tEnd = CanvasGeometry.trimTBeforeTip(
                        from: p1,
                        fromSide: fromSide,
                        to: p2,
                        toSide: toSide,
                        distance: worldArrow
                    )
                }
                if showsFrom {
                    let reverseT = CanvasGeometry.trimTBeforeTip(
                        from: p2,
                        fromSide: toSide ?? fromSide.opposite,
                        to: p1,
                        toSide: fromSide,
                        distance: worldArrow
                    )
                    tStart = min(max(1 - reverseT, 0), max(tEnd - 0.02, 0))
                }

                let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let segments: [(CGFloat, CGFloat)]
                if trimmedLabel.isEmpty {
                    segments = [(min(tStart, 0.98), max(min(tEnd, 0.998), tStart + 0.01))]
                } else {
                    let gapHalf = min(0.18, 0.05 + CGFloat(trimmedLabel.count) * 0.012)
                    let gapStart = max(tStart, 0.5 - gapHalf)
                    let gapEnd = min(tEnd, 0.5 + gapHalf)
                    segments = [
                        (min(tStart, 0.98), max(gapStart, tStart + 0.01)),
                        (min(gapEnd, 0.998), max(min(tEnd, 0.998), gapEnd + 0.01))
                    ].filter { $0.1 > $0.0 + 0.005 }
                }

                func drawSegment(_ start: CGFloat, _ end: CGFloat) {
                    let trimmed = worldPath.trimmedPath(from: start, to: end)
                    let linePath = transformPath(trimmed, toScreen: toScreen)
                    let style = { (width: CGFloat) in
                        StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round)
                    }
                    context.stroke(linePath, with: strokeSet.0, style: style(glowW))
                    context.stroke(linePath, with: strokeSet.1, style: style(bodyW))
                    context.stroke(linePath, with: strokeSet.2, style: style(coreW))
                }

                for segment in segments {
                    drawSegment(segment.0, segment.1)
                }

                if showsTo {
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
                    drawArrowHead(at: tip, toward: nearTip, stroke: strokeSet)
                }

                if showsFrom {
                    let tip = toScreen(p1)
                    let nearTip = toScreen(
                        CanvasGeometry.pointOnCurve(
                            from: p1,
                            fromSide: fromSide,
                            to: p2,
                            toSide: toSide,
                            t: min(tStart + 0.05, 1)
                        )
                    )
                    drawArrowHead(at: tip, toward: nearTip, stroke: strokeSet)
                }
            }

            func effectiveLabel(for edge: CanvasEdge) -> String? {
                if edge.id == editingEdgeID {
                    return editingLabelDraft
                }
                return edge.label
            }

            for edge in edges {
                guard let from = cardIndex[edge.fromID] else { continue }
                let p1 = CanvasGeometry.anchor(for: from, side: edge.fromSide, overrides: positionOverrides, resizeOverrides: resizeOverrides)
                let isSelected = edge.id == selectedEdgeID
                let stroke = edgeStrokeSet(for: edge, isSelected: isSelected)

                if let toID = edge.toID, let to = cardIndex[toID] {
                    let side = edge.toSide ?? .left
                    drawEdge(
                        from: p1,
                        fromSide: edge.fromSide,
                        to: CanvasGeometry.anchor(for: to, side: side, overrides: positionOverrides, resizeOverrides: resizeOverrides),
                        toSide: side,
                        direction: edge.direction,
                        isSelected: isSelected,
                        label: effectiveLabel(for: edge),
                        stroke: stroke
                    )
                } else if let point = edge.toPoint {
                    drawEdge(
                        from: p1,
                        fromSide: edge.fromSide,
                        to: point,
                        toSide: nil,
                        direction: edge.direction,
                        isSelected: isSelected,
                        label: effectiveLabel(for: edge),
                        stroke: stroke
                    )
                }
            }

            if let connecting = connectingFrom, let from = cardIndex[connecting.cardID] {
                let p1 = CanvasGeometry.anchor(for: from, side: connecting.side, overrides: positionOverrides, resizeOverrides: resizeOverrides)
                drawEdge(
                    from: p1,
                    fromSide: connecting.side,
                    to: CGPoint(x: connecting.toX, y: connecting.toY),
                    toSide: nil,
                    direction: .unidirectional
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func edgeLineScreenScale(for zoom: CGFloat) -> CGFloat {
        min(1, max(0.22, zoom))
    }

    private func edgeStrokeColor(from hex: String?) -> Color? {
        guard let hex else { return nil }
        return Color(hexString: hex)
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
