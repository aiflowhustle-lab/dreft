import SwiftUI

enum CanvasGeometry {
    static func bezierPath(from p1: CGPoint, fromSide: CanvasSide, to p2: CGPoint, toSide: CanvasSide?) -> Path {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let dist = hypot(dx, dy)
        let tension = max(80, dist * 0.55)

        let n1 = fromSide.normal(dx: dx, dy: dy)
        let n2: CGPoint = {
            if let toSide { return toSide.normal(dx: -dx, dy: -dy) }
            let len = max(hypot(dx, dy), 1)
            return CGPoint(x: -dx / len, y: -dy / len)
        }()

        let c1 = CGPoint(x: p1.x + n1.x * tension, y: p1.y + n1.y * tension)
        let c2 = CGPoint(x: p2.x + n2.x * tension, y: p2.y + n2.y * tension)

        var path = Path()
        path.move(to: p1)
        path.addCurve(to: p2, control1: c1, control2: c2)
        return path
    }

    static func arrowHead(at tip: CGPoint, toward origin: CGPoint, size: CGFloat = 12) -> Path {
        let dx = tip.x - origin.x
        let dy = tip.y - origin.y
        let len = max(hypot(dx, dy), 1)
        let ux = dx / len
        let uy = dy / len
        let px = -uy
        let py = ux
        let base = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x + px * size * 0.58, y: base.y + py * size * 0.58))
        path.addLine(to: CGPoint(x: base.x - px * size * 0.58, y: base.y - py * size * 0.58))
        path.closeSubpath()
        return path
    }

    static func pointOnCurve(from p1: CGPoint, fromSide: CanvasSide, to p2: CGPoint, toSide: CanvasSide?, t: CGFloat) -> CGPoint {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let dist = hypot(dx, dy)
        let tension = max(80, dist * 0.55)
        let n1 = fromSide.normal(dx: dx, dy: dy)
        let n2: CGPoint = {
            if let toSide { return toSide.normal(dx: -dx, dy: -dy) }
            let len = max(hypot(dx, dy), 1)
            return CGPoint(x: -dx / len, y: -dy / len)
        }()
        let c1 = CGPoint(x: p1.x + n1.x * tension, y: p1.y + n1.y * tension)
        let c2 = CGPoint(x: p2.x + n2.x * tension, y: p2.y + n2.y * tension)
        let u = 1 - t
        return CGPoint(
            x: u * u * u * p1.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p2.x,
            y: u * u * u * p1.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p2.y
        )
    }

    /// Parameter `t` along the curve where straight-line distance to `p2` equals `distance`.
    static func trimTBeforeTip(
        from p1: CGPoint,
        fromSide: CanvasSide,
        to p2: CGPoint,
        toSide: CanvasSide?,
        distance: CGFloat
    ) -> CGFloat {
        guard distance > 0 else { return 1 }
        var lo: CGFloat = 0
        var hi: CGFloat = 1
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let pt = pointOnCurve(from: p1, fromSide: fromSide, to: p2, toSide: toSide, t: mid)
            if hypot(p2.x - pt.x, p2.y - pt.y) > distance {
                lo = mid
            } else {
                hi = mid
            }
        }
        return max(lo, 0.02)
    }

    static func nearestSide(for point: CGPoint, in rect: CGRect) -> CanvasSide {
        let dL = abs(point.x - rect.minX)
        let dR = abs(point.x - rect.maxX)
        let dT = abs(point.y - rect.minY)
        let dB = abs(point.y - rect.maxY)
        let minD = min(dL, dR, dT, dB)
        if minD == dL { return .left }
        if minD == dR { return .right }
        if minD == dT { return .top }
        return .bottom
    }

    static func cardRect(
        _ card: CanvasCard,
        overrides: [String: CGPoint],
        resizeOverrides: [String: CGRect] = [:]
    ) -> CGRect {
        if let frame = resizeOverrides[card.id] { return frame }
        let origin = overrides[card.id] ?? CGPoint(x: card.x, y: card.y)
        return CGRect(x: origin.x, y: origin.y, width: card.width, height: card.height)
    }

    static func anchor(in rect: CGRect, side: CanvasSide) -> CGPoint {
        switch side {
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        }
    }

    static func anchor(for card: CanvasCard, side: CanvasSide, overrides: [String: CGPoint], resizeOverrides: [String: CGRect] = [:]) -> CGPoint {
        anchor(in: cardRect(card, overrides: overrides, resizeOverrides: resizeOverrides), side: side)
    }

    /// Minimum screen-space distance from `screenPoint` to a connection curve.
    static func screenDistanceToEdge(
        screenPoint: CGPoint,
        from p1: CGPoint,
        fromSide: CanvasSide,
        to p2: CGPoint,
        toSide: CanvasSide?,
        toScreen: (CGPoint) -> CGPoint
    ) -> CGFloat {
        let samples = 28
        var minDistance = CGFloat.greatestFiniteMagnitude
        for index in 0...samples {
            let t = CGFloat(index) / CGFloat(samples)
            let worldPoint = pointOnCurve(from: p1, fromSide: fromSide, to: p2, toSide: toSide, t: t)
            let screen = toScreen(worldPoint)
            minDistance = min(minDistance, hypot(screenPoint.x - screen.x, screenPoint.y - screen.y))
        }
        return minDistance
    }

    static func cardOrigin(connectingSide: CanvasSide, at point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        switch connectingSide {
        case .left: CGPoint(x: point.x, y: point.y - height / 2)
        case .right: CGPoint(x: point.x - width, y: point.y - height / 2)
        case .top: CGPoint(x: point.x - width / 2, y: point.y)
        case .bottom: CGPoint(x: point.x - width / 2, y: point.y - height)
        }
    }

    /// Side of a card that should face/connect toward `target`, given a point on that side.
    static func sideFacing(toward target: CGPoint, from edgePoint: CGPoint) -> CanvasSide {
        let dx = target.x - edgePoint.x
        let dy = target.y - edgePoint.y
        if abs(dx) >= abs(dy) {
            return dx < 0 ? .left : .right
        }
        return dy < 0 ? .top : .bottom
    }

    /// Card placement that keeps the edge endpoint at the arrow tip for a smooth curve.
    static func endpointCardPlacement(
        sourceAnchor: CGPoint,
        arrowTip: CGPoint,
        menuCenter: CGPoint,
        cardWidth: CGFloat,
        cardHeight: CGFloat
    ) -> (origin: CGPoint, connectingSide: CanvasSide) {
        let dx = arrowTip.x - sourceAnchor.x
        let dy = arrowTip.y - sourceAnchor.y
        let length = max(hypot(dx, dy), 1)
        let ux = dx / length
        let uy = dy / length

        // Keep the connection on the arrow tip; align the other axis with the menu.
        let attachPoint: CGPoint = abs(ux) >= abs(uy)
            ? CGPoint(x: arrowTip.x, y: menuCenter.y)
            : CGPoint(x: menuCenter.x, y: arrowTip.y)

        let connectingSide = sideFacing(toward: sourceAnchor, from: attachPoint)
        let origin = cardOrigin(
            connectingSide: connectingSide,
            at: attachPoint,
            width: cardWidth,
            height: cardHeight
        )
        return (origin, connectingSide)
    }
}

/// Connection lines drawn above cards — Obsidian-style tubular gray curves.
struct CanvasEdgesView: View {
    let cardIndex: [String: CanvasCard]
    let edges: [CanvasEdge]
    let connectingFrom: (cardID: String, side: CanvasSide, toX: CGFloat, toY: CGFloat)?
    let positionOverrides: [String: CGPoint]
    let resizeOverrides: [String: CGRect]
    let zoom: CGFloat

    var body: some View {
        Canvas { context, _ in
            let z = max(zoom, 0.08)
            let glowW = 15 / z
            let bodyW = 6.5 / z
            let coreW = 3.2 / z
            let arrowSize = CanvasConstants.edgeArrowScreenSize / z
            let join = StrokeStyle(lineCap: .round, lineJoin: .round)

            let glowColor = GraphicsContext.Shading.color(AppColors.edgeOuter)
            let bodyColor = GraphicsContext.Shading.color(AppColors.edgeStroke)
            let coreColor = GraphicsContext.Shading.color(AppColors.edgeHighlight)

            func drawTube(_ path: Path, cap: CGLineCap) {
                context.stroke(path, with: glowColor, style: StrokeStyle(lineWidth: glowW, lineCap: cap, lineJoin: join.lineJoin))
                context.stroke(path, with: bodyColor, style: StrokeStyle(lineWidth: bodyW, lineCap: cap, lineJoin: join.lineJoin))
                context.stroke(path, with: coreColor, style: StrokeStyle(lineWidth: coreW, lineCap: cap, lineJoin: join.lineJoin))
            }

            func drawArrowHead(at tip: CGPoint, toward origin: CGPoint, size: CGFloat) {
                let glow = CanvasGeometry.arrowHead(at: tip, toward: origin, size: size + 4 / z)
                let body = CanvasGeometry.arrowHead(at: tip, toward: origin, size: size)
                let core = CanvasGeometry.arrowHead(at: tip, toward: origin, size: size * 0.45)
                context.fill(glow, with: glowColor)
                context.fill(body, with: bodyColor)
                context.fill(core, with: coreColor)
            }

            func drawEdge(from p1: CGPoint, fromSide: CanvasSide, to p2: CGPoint, toSide: CanvasSide?, showsArrow: Bool) {
                let path = CanvasGeometry.bezierPath(from: p1, fromSide: fromSide, to: p2, toSide: toSide)

                if showsArrow {
                    let tEnd = CanvasGeometry.trimTBeforeTip(
                        from: p1,
                        fromSide: fromSide,
                        to: p2,
                        toSide: toSide,
                        distance: arrowSize
                    )
                    drawTube(path.trimmedPath(from: 0, to: min(tEnd, 0.998)), cap: .butt)

                    let nearTip = CanvasGeometry.pointOnCurve(from: p1, fromSide: fromSide, to: p2, toSide: toSide, t: max(tEnd - 0.05, 0))
                    drawArrowHead(at: p2, toward: nearTip, size: arrowSize)
                } else {
                    drawTube(path, cap: .round)
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
        .frame(width: CanvasConstants.worldSize, height: CanvasConstants.worldSize)
        .allowsHitTesting(false)
    }
}
