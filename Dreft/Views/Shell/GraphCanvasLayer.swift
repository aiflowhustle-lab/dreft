import SwiftUI

struct GraphCanvasLink: Identifiable, Hashable {
    let fromID: String
    let toID: String

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

/// Single-pass Canvas renderer for graph links and node dots.
/// Labels render in Canvas while the layout animates, and as native Text once settled.
struct GraphCanvasLayer: View {
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

    var body: some View {
        Canvas { context, _ in
            drawLinks(in: &context)
            drawNodes(in: &context)
        }
        .allowsHitTesting(false)
    }

    private func drawLinks(in context: inout GraphicsContext) {
        guard linkRenderOpacity > 0.01 else { return }
        let baseOpacity = linksDimmed ? 0.16 : 0.45
        let linkColor = Color.white.opacity(baseOpacity * linkRenderOpacity)

        for link in links {
            guard let from = positions[link.fromID],
                  let to = positions[link.toID] else { continue }

            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(
                path,
                with: .color(linkColor),
                style: StrokeStyle(lineWidth: linkStrokeWidth, lineCap: .round)
            )

            if showArrows {
                drawArrow(in: &context, from: from, to: to, color: linkColor)
            }
        }
    }

    private func drawArrow(in context: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        let delta = CGPoint(x: to.x - from.x, y: to.y - from.y)
        let length = max(hypot(delta.x, delta.y), 1)
        let direction = CGPoint(x: delta.x / length, y: delta.y / length)
        let tip = to
        let wing = CGPoint(x: -direction.y, y: direction.x)
        let base = CGPoint(x: tip.x - direction.x * 10, y: tip.y - direction.y * 10)

        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x + wing.x * 4, y: base.y + wing.y * 4))
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x - wing.x * 4, y: base.y - wing.y * 4))
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: linkStrokeWidth, lineCap: .round)
        )
    }

    private func drawNodes(in context: inout GraphicsContext) {
        for node in nodes {
            let nodeOpacity = node.isDimmed ? 0.22 : 1.0
            let layout = nodeLayout(for: node.position, dotSize: nodeDotSize, isActive: node.isActive)
            let dotColor = node.isActive
                ? AppColors.selectionStroke
                : (node.groupColor ?? Color.white.opacity(0.92))

            if node.isActive {
                let haloRect = CGRect(
                    x: layout.dotCenter.x - layout.activeDotRadius - 5.5,
                    y: layout.dotCenter.y - layout.activeDotRadius - 5.5,
                    width: (layout.activeDotRadius + 5.5) * 2,
                    height: (layout.activeDotRadius + 5.5) * 2
                )
                context.fill(
                    Path(ellipseIn: haloRect),
                    with: .color(AppColors.selectionStroke.opacity(0.25 * nodeOpacity))
                )
            }

            let dotRect = CGRect(
                x: layout.dotCenter.x - layout.activeDotRadius,
                y: layout.dotCenter.y - layout.activeDotRadius,
                width: layout.activeDotRadius * 2,
                height: layout.activeDotRadius * 2
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(dotColor.opacity(nodeOpacity)))

            guard drawLabelsInCanvas, labelOpacity > 0.01, node.showsLabel else { continue }

            let labelColor = node.isActive
                ? AppColors.selectionStroke.opacity(0.95 * labelOpacity * nodeOpacity)
                : Color.white.opacity(0.88 * labelOpacity * nodeOpacity)
            let labelText = Text(node.label)
                .font(.system(size: 11, weight: node.isActive ? .semibold : .regular))
                .foregroundStyle(labelColor)
            let resolved = context.resolve(labelText)
            context.draw(
                resolved,
                at: CGPoint(x: layout.labelCenter.x, y: layout.labelCenter.y),
                anchor: .center
            )
        }
    }

    private struct NodeLayout {
        let dotCenter: CGPoint
        let activeDotRadius: CGFloat
        let labelCenter: CGPoint
    }

    private func nodeLayout(for position: CGPoint, dotSize: CGFloat, isActive: Bool) -> NodeLayout {
        let dotRadius = (isActive ? dotSize + 2 : dotSize) / 2
        // Match the old SwiftUI stack: dot above label, combined view centered on `position`.
        let dotCenter = CGPoint(x: position.x, y: position.y - 12)
        let labelCenter = CGPoint(x: position.x, y: position.y + 18)
        return NodeLayout(dotCenter: dotCenter, activeDotRadius: dotRadius, labelCenter: labelCenter)
    }
}

/// Native SwiftUI labels — crisp subpixel text like Obsidian, unlike Canvas rasterization.
struct GraphNodeLabelsLayer: View {
    @Environment(\.displayScale) private var displayScale

    let nodes: [GraphCanvasDrawNode]
    let labelOpacity: CGFloat

    var body: some View {
        ZStack {
            ForEach(nodes) { node in
                if labelOpacity > 0.01, node.showsLabel {
                    Text(node.label)
                        .font(.system(size: 11, weight: node.isActive ? .semibold : .regular))
                        .foregroundStyle(labelColor(for: node))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 120)
                        .position(labelCenter(for: node.position))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func labelColor(for node: GraphCanvasDrawNode) -> Color {
        let nodeOpacity = node.isDimmed ? 0.22 : 1.0
        if node.isActive {
            return AppColors.selectionStroke.opacity(0.95 * labelOpacity * nodeOpacity)
        }
        return Color.white.opacity(0.88 * labelOpacity * nodeOpacity)
    }

    private func labelCenter(for position: CGPoint) -> CGPoint {
        snapToPixel(CGPoint(x: position.x, y: position.y + 18), scale: displayScale)
    }

    private func snapToPixel(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (point.x * scale).rounded() / scale,
            y: (point.y * scale).rounded() / scale
        )
    }
}

enum GraphCanvasHitTesting {
    /// Matches the combined dot + label hit area from the previous GraphNodeView layout.
    static func nodeID(at point: CGPoint, in nodes: [GraphCanvasDrawNode]) -> String? {
        for node in nodes.reversed() {
            let layout = nodeLayout(for: node.position)
            let hitRect = layout.labelRect
                .union(CGRect(
                    x: layout.dotCenter.x - 16,
                    y: layout.dotCenter.y - 16,
                    width: 32,
                    height: 32
                ))
            if hitRect.contains(point) {
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
        let dotCenter = CGPoint(x: position.x, y: position.y - 12)
        let labelRect = CGRect(x: position.x - 60, y: position.y + 2, width: 120, height: 32)
        return NodeLayout(dotCenter: dotCenter, labelRect: labelRect)
    }
}
