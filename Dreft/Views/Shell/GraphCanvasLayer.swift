import SwiftUI

struct GraphCanvasLink: Identifiable, Hashable {
    let fromID: String
    let toID: String
    var isDimmed: Bool = false

    var id: String { "\(fromID)->\(toID)" }
}

struct GraphCanvasDrawNode: Identifiable {
    let id: String
    let label: String
    let position: CGPoint
    let isActive: Bool
    let isDimmed: Bool
    let groupColor: Color?
    var showsLabel: Bool = true
}

enum GraphNodeLayoutMetrics {
    /// Dot center sits this many points above the layout anchor.
    static let dotLift: CGFloat = 7
    /// Label center sits this many points below the layout anchor.
    static let labelDrop: CGFloat = 7
    static let labelWidth: CGFloat = 120
    static let labelLineHeight: CGFloat = 13

    static func dotCenter(for anchor: CGPoint, zoom: CGFloat = 1) -> CGPoint {
        CGPoint(x: anchor.x, y: anchor.y - dotLift * zoom)
    }

    static func labelCenter(for anchor: CGPoint, zoom: CGFloat = 1) -> CGPoint {
        CGPoint(x: anchor.x, y: anchor.y + labelDrop * zoom)
    }

    static func labelRect(for anchor: CGPoint, zoom: CGFloat = 1) -> CGRect {
        let center = labelCenter(for: anchor, zoom: zoom)
        let width = labelWidth * zoom
        let height = labelLineHeight * zoom
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }
}

enum GraphScreenTransform {
    static func worldToScreen(_ world: CGPoint, zoom: CGFloat, pan: CGSize) -> CGPoint {
        CGPoint(x: world.x * zoom + pan.width, y: world.y * zoom + pan.height)
    }

    static func screenToWorld(_ screen: CGPoint, zoom: CGFloat, pan: CGSize) -> CGPoint {
        let z = max(zoom, 0.01)
        return CGPoint(x: (screen.x - pan.width) / z, y: (screen.y - pan.height) / z)
    }
}

/// Renders graph links and node dots in screen space at native resolution for the current zoom.
struct GraphCanvasLayer: View {
    @Environment(\.displayScale) private var displayScale

    let nodes: [GraphCanvasDrawNode]
    let links: [GraphCanvasLink]
    let positions: [String: CGPoint]
    let linkStrokeWidth: CGFloat
    let showArrows: Bool
    let nodeDotSize: CGFloat
    let labelOpacity: CGFloat
    let drawLabelsInCanvas: Bool
    let linksDimmed: Bool
    var linkRenderOpacity: CGFloat = 1
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    private var layoutZoom: CGFloat { max(zoom, 0.01) }

    var body: some View {
        Canvas { context, _ in
            let pixelScale = displayScale
            drawLinks(in: &context, pixelScale: pixelScale)
            drawNodes(in: &context, pixelScale: pixelScale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func snapToPixel(_ point: CGPoint, pixelScale: CGFloat) -> CGPoint {
        CGPoint(
            x: (point.x * pixelScale).rounded() / pixelScale,
            y: (point.y * pixelScale).rounded() / pixelScale
        )
    }

    private func snapDotDiameter(_ diameter: CGFloat, pixelScale: CGFloat) -> CGFloat {
        let diameterPx = max((diameter * pixelScale).rounded(), 2)
        let evenDiameterPx = Int(diameterPx) % 2 == 0 ? diameterPx : diameterPx + 1
        return max(evenDiameterPx / pixelScale, 1 / pixelScale)
    }

    private func screenDotCenter(for world: CGPoint) -> CGPoint {
        let anchor = GraphScreenTransform.worldToScreen(world, zoom: layoutZoom, pan: pan)
        return GraphNodeLayoutMetrics.dotCenter(for: anchor, zoom: layoutZoom)
    }

    private func screenLabelCenter(for world: CGPoint) -> CGPoint {
        let anchor = GraphScreenTransform.worldToScreen(world, zoom: layoutZoom, pan: pan)
        return GraphNodeLayoutMetrics.labelCenter(for: anchor, zoom: layoutZoom)
    }

    private func drawLinks(in context: inout GraphicsContext, pixelScale: CGFloat) {
        guard linkRenderOpacity > 0.01 else { return }
        let linkColor = (linksDimmed ? AppColors.graphLinkDimmedColor : AppColors.graphLinkColor)
            .opacity(linkRenderOpacity)
        let strokeWidth = linkStrokeWidth * layoutZoom

        let radiusByID = Dictionary(uniqueKeysWithValues: nodes.map { node in
            let diameter = node.isActive ? nodeDotSize + 2 : nodeDotSize
            return (node.id, snapDotDiameter(diameter * layoutZoom, pixelScale: pixelScale) / 2)
        })

        for link in links {
            guard let fromPos = positions[link.fromID],
                  let toPos = positions[link.toID] else { continue }

            let fromCenter = snapToPixel(screenDotCenter(for: fromPos), pixelScale: pixelScale)
            let toCenter = snapToPixel(screenDotCenter(for: toPos), pixelScale: pixelScale)
            let fromRadius = radiusByID[link.fromID] ?? snapDotDiameter(nodeDotSize * layoutZoom, pixelScale: pixelScale) / 2
            let toRadius = radiusByID[link.toID] ?? snapDotDiameter(nodeDotSize * layoutZoom, pixelScale: pixelScale) / 2

            let start = snapToPixel(
                edgePoint(from: fromCenter, toward: toCenter, radius: fromRadius),
                pixelScale: pixelScale
            )
            let end = snapToPixel(
                edgePoint(from: toCenter, toward: fromCenter, radius: toRadius),
                pixelScale: pixelScale
            )

            let strokeColor = link.isDimmed ? linkColor.opacity(0.12) : linkColor

            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(
                path,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )

            if showArrows {
                drawArrow(in: &context, from: start, to: end, color: strokeColor, strokeWidth: strokeWidth)
            }
        }
    }

    private func drawArrow(
        in context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        color: Color,
        strokeWidth: CGFloat
    ) {
        let delta = CGPoint(x: to.x - from.x, y: to.y - from.y)
        let length = max(hypot(delta.x, delta.y), 1)
        let direction = CGPoint(x: delta.x / length, y: delta.y / length)
        let tip = to
        let wing = CGPoint(x: -direction.y, y: direction.x)
        let arrowLength = 10 * layoutZoom
        let wingSpread = 4 * layoutZoom
        let base = CGPoint(x: tip.x - direction.x * arrowLength, y: tip.y - direction.y * arrowLength)

        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x + wing.x * wingSpread, y: base.y + wing.y * wingSpread))
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x - wing.x * wingSpread, y: base.y - wing.y * wingSpread))
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
        )
    }

    private func edgePoint(from center: CGPoint, toward other: CGPoint, radius: CGFloat) -> CGPoint {
        let dx = other.x - center.x
        let dy = other.y - center.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return center }
        let inset = min(radius + (0.75 * layoutZoom), length * 0.42)
        let t = inset / length
        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }

    private func drawNodes(in context: inout GraphicsContext, pixelScale: CGFloat) {
        for node in nodes {
            let nodeOpacity = node.isDimmed ? 0.22 : 1.0
            let baseDiameter = (node.isActive ? nodeDotSize + 2 : nodeDotSize) * layoutZoom
            let diameter = snapDotDiameter(baseDiameter, pixelScale: pixelScale)
            let radius = diameter / 2
            let dotCenter = snapToPixel(screenDotCenter(for: node.position), pixelScale: pixelScale)
            let dotColor = node.isActive
                ? AppColors.selectionStroke
                : (node.groupColor ?? AppColors.graphNodeColor)

            if node.isActive {
                let haloPad = 5.5 * layoutZoom
                let haloRect = CGRect(
                    x: dotCenter.x - radius - haloPad,
                    y: dotCenter.y - radius - haloPad,
                    width: (radius + haloPad) * 2,
                    height: (radius + haloPad) * 2
                )
                context.fill(
                    Path(ellipseIn: haloRect),
                    with: .color(AppColors.selectionStroke.opacity(0.25 * nodeOpacity))
                )
            }

            let dotRect = CGRect(
                x: dotCenter.x - radius,
                y: dotCenter.y - radius,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(dotColor.opacity(nodeOpacity)))

            guard drawLabelsInCanvas, labelOpacity > 0.01, node.showsLabel else { continue }

            let labelCenter = snapToPixel(screenLabelCenter(for: node.position), pixelScale: pixelScale)
            let labelColor = node.isActive
                ? AppColors.selectionStroke.opacity(0.95 * labelOpacity * nodeOpacity)
                : AppColors.graphLabelColor.opacity(labelOpacity * nodeOpacity)
            let labelText = Text(node.label)
                .font(.system(size: 11 * layoutZoom, weight: node.isActive ? .semibold : .regular))
                .foregroundStyle(labelColor)
            let resolved = context.resolve(labelText)
            context.draw(resolved, at: labelCenter, anchor: .center)
        }
    }
}

/// Native SwiftUI labels rendered in screen space — crisp at every zoom level.
struct GraphNodeLabelsLayer: View {
    @Environment(\.displayScale) private var displayScale

    let nodes: [GraphCanvasDrawNode]
    let labelOpacity: CGFloat
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    private var layoutZoom: CGFloat { max(zoom, 0.01) }

    var body: some View {
        ZStack {
            ForEach(nodes) { node in
                if labelOpacity > 0.01, node.showsLabel {
                    Text(node.label)
                        .font(.system(size: 11 * layoutZoom, weight: node.isActive ? .semibold : .regular))
                        .foregroundStyle(labelColor(for: node))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: GraphNodeLayoutMetrics.labelWidth * layoutZoom)
                        .position(labelCenter(for: node.position))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func labelColor(for node: GraphCanvasDrawNode) -> Color {
        let nodeOpacity = node.isDimmed ? 0.22 : 1.0
        if node.isActive {
            return AppColors.selectionStroke.opacity(0.95 * labelOpacity * nodeOpacity)
        }
        return AppColors.graphLabelColor.opacity(labelOpacity * nodeOpacity)
    }

    private func labelCenter(for position: CGPoint) -> CGPoint {
        let anchor = GraphScreenTransform.worldToScreen(position, zoom: layoutZoom, pan: pan)
        return snapToPixel(
            GraphNodeLayoutMetrics.labelCenter(for: anchor, zoom: layoutZoom),
            pixelScale: displayScale
        )
    }

    private func snapToPixel(_ point: CGPoint, pixelScale: CGFloat) -> CGPoint {
        CGPoint(
            x: (point.x * pixelScale).rounded() / pixelScale,
            y: (point.y * pixelScale).rounded() / pixelScale
        )
    }
}

enum GraphCanvasHitTesting {
    #if os(iOS)
    /// Minimum on-screen touch target (points) for graph node taps.
    private static let minTouchTargetScreen: CGFloat = 44
    #else
    private static let minTouchTargetScreen: CGFloat = 20
    #endif

    static func nodeID(
        at worldPoint: CGPoint,
        in nodes: [GraphCanvasDrawNode],
        zoom: CGFloat = 1,
        dotOnly: Bool = false
    ) -> String? {
        let z = max(zoom, 0.01)
        for node in nodes.reversed() {
            let layout = nodeLayout(for: node.position)
            let hitRect: CGRect
            if dotOnly {
                let pad = max(14, minTouchTargetScreen / (2 * z))
                hitRect = CGRect(
                    x: layout.dotCenter.x - pad,
                    y: layout.dotCenter.y - pad,
                    width: pad * 2,
                    height: pad * 2
                )
            } else {
                let dotPad = max(16, minTouchTargetScreen / (2 * z))
                hitRect = layout.labelRect
                    .union(CGRect(
                        x: layout.dotCenter.x - dotPad,
                        y: layout.dotCenter.y - dotPad,
                        width: dotPad * 2,
                        height: dotPad * 2
                    ))
            }
            if hitRect.contains(worldPoint) {
                return node.id
            }
        }
        return nil
    }

    private struct NodeLayout {
        let dotCenter: CGPoint
        let labelRect: CGRect
    }

    private static func nodeLayout(for position: CGPoint) -> NodeLayout {
        let dotCenter = GraphNodeLayoutMetrics.dotCenter(for: position)
        let labelRect = GraphNodeLayoutMetrics.labelRect(for: position)
        return NodeLayout(dotCenter: dotCenter, labelRect: labelRect)
    }
}
