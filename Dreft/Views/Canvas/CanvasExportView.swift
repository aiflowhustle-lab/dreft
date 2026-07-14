import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CanvasExportView: View {
    let snapshot: CanvasDocumentSnapshot
    let vaultURL: URL?
    var cropBounds: CGRect?
    var requestedScale: CGFloat = 1
    var showLogo = true
    var privacyMode = false

    private let padding: CGFloat = 40
    static let maximumEdge: CGFloat = 16_384
    static let maximumPixels: CGFloat = 100_000_000

    private var worldBounds: CGRect {
        cropBounds ?? Self.fullCanvasBounds(for: snapshot, padding: padding)
    }

    private var exportScale: CGFloat {
        Self.effectiveScale(for: worldBounds, requestedScale: requestedScale)
    }

    private var outputSize: CGSize {
        CGSize(
            width: max(1, worldBounds.width * exportScale),
            height: max(1, worldBounds.height * exportScale)
        )
    }

    private var exportTransform: CGAffineTransform {
        CGAffineTransform(
            a: exportScale,
            b: 0,
            c: 0,
            d: exportScale,
            tx: -worldBounds.minX * exportScale,
            ty: -worldBounds.minY * exportScale
        )
    }

    private var cardIndex: [String: CanvasCard] {
        Dictionary(uniqueKeysWithValues: snapshot.cards.map { ($0.id, $0) })
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AppColors.canvasBackground

            Canvas { context, size in
                drawGrid(context: &context, size: size)
                drawEdges(context: &context)
            }

            ForEach(snapshot.edges) { edge in
                if let label = edge.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !label.isEmpty,
                   let midpoint = edgeMidpoint(for: edge) {
                    exportEdgeLabel(label, at: midpoint)
                }
            }

            ForEach(snapshot.cards) { card in
                if CGRect(x: card.x, y: card.y, width: card.width, height: card.height)
                    .intersects(worldBounds) {
                    exportCard(card)
                        .frame(
                            width: max(1, card.width * exportScale),
                            height: max(1, card.height * exportScale)
                        )
                        .position(
                            x: (card.x - worldBounds.minX + card.width / 2) * exportScale,
                            y: (card.y - worldBounds.minY + card.height / 2) * exportScale
                        )
                }
            }

            if showLogo {
                HStack(spacing: 8) {
                    DreftGemLogo()
                        .frame(width: 28, height: 28)
                    Text("Dreft")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(width: outputSize.width, height: outputSize.height)
    }

    private func exportEdgeLabel(_ text: String, at worldPoint: CGPoint) -> some View {
        Text(text)
            .font(.system(size: max(7, 13 * exportScale), weight: .regular))
            .foregroundStyle(AppColors.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, max(3, 6 * exportScale))
            .padding(.vertical, max(1, 2 * exportScale))
            .background(AppColors.canvasBackground)
            .position(
                x: (worldPoint.x - worldBounds.minX) * exportScale,
                y: (worldPoint.y - worldBounds.minY) * exportScale
            )
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        let spacing = max(8, CanvasConstants.dotSpacing * exportScale)
        let dotSize = max(2, CanvasConstants.dotSize * exportScale)
        let offsetX = CanvasMath.positiveModulo(
            -worldBounds.minX * exportScale,
            divisor: spacing
        )
        let offsetY = CanvasMath.positiveModulo(
            -worldBounds.minY * exportScale,
            divisor: spacing
        )
        var x = offsetX
        while x < size.width {
            var y = offsetY
            while y < size.height {
                let dot = Path(
                    ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)
                )
                context.fill(dot, with: .color(AppColors.gridDotColor))
                y += spacing
            }
            x += spacing
        }
    }

    private func drawEdges(context: inout GraphicsContext) {
        let lineScale = min(1, max(0.22, exportScale))
        let glowW: CGFloat = 14 * lineScale
        let bodyW: CGFloat = 6.5 * lineScale
        let coreW: CGFloat = 3.2 * lineScale
        let arrowSize = CanvasConstants.edgeArrowScreenSize * lineScale
        let worldArrow = arrowSize / max(exportScale, 0.08)

        let glowColor = GraphicsContext.Shading.color(AppColors.edgeOuter)
        let bodyColor = GraphicsContext.Shading.color(AppColors.edgeStroke)
        let coreColor = GraphicsContext.Shading.color(AppColors.edgeHighlight)

        for edge in snapshot.edges {
            guard let from = cardIndex[edge.fromID] else { continue }
            let p1 = CanvasGeometry.anchor(
                for: from,
                side: edge.fromSide,
                overrides: [:],
                resizeOverrides: [:]
            )

            let p2: CGPoint
            let toSide: CanvasSide?
            if let toID = edge.toID, let to = cardIndex[toID] {
                let side = edge.toSide ?? .left
                p2 = CanvasGeometry.anchor(
                    for: to,
                    side: side,
                    overrides: [:],
                    resizeOverrides: [:]
                )
                toSide = side
            } else if let point = edge.toPoint {
                p2 = point
                toSide = nil
            } else {
                continue
            }

            let strokeSet = edgeStrokeSet(
                for: edge,
                glowColor: glowColor,
                bodyColor: bodyColor,
                coreColor: coreColor
            )
            let worldPath = CanvasGeometry.bezierPath(
                from: p1,
                fromSide: edge.fromSide,
                to: p2,
                toSide: toSide
            )

            var tStart: CGFloat = 0
            var tEnd: CGFloat = 1
            if edge.direction.showsToArrow {
                tEnd = CanvasGeometry.trimTBeforeTip(
                    from: p1,
                    fromSide: edge.fromSide,
                    to: p2,
                    toSide: toSide,
                    distance: worldArrow
                )
            }
            if edge.direction.showsFromArrow {
                let reverseT = CanvasGeometry.trimTBeforeTip(
                    from: p2,
                    fromSide: toSide ?? edge.fromSide.opposite,
                    to: p1,
                    toSide: edge.fromSide,
                    distance: worldArrow
                )
                tStart = min(max(1 - reverseT, 0), max(tEnd - 0.02, 0))
            }

            let trimmedLabel = edge.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

            for segment in segments {
                let trimmed = worldPath.trimmedPath(from: segment.0, to: segment.1)
                let linePath = trimmed.applying(exportTransform)
                let style = { (width: CGFloat) in
                    StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round)
                }
                context.stroke(linePath, with: strokeSet.0, style: style(glowW))
                context.stroke(linePath, with: strokeSet.1, style: style(bodyW))
                context.stroke(linePath, with: strokeSet.2, style: style(coreW))
            }

            if edge.direction.showsToArrow {
                let tip = CGPoint(x: p2.x, y: p2.y).applying(exportTransform)
                let nearTip = CanvasGeometry.pointOnCurve(
                    from: p1,
                    fromSide: edge.fromSide,
                    to: p2,
                    toSide: toSide,
                    t: max(tEnd - 0.05, 0)
                ).applying(exportTransform)
                drawArrowHead(
                    context: &context,
                    at: tip,
                    toward: nearTip,
                    size: arrowSize,
                    stroke: strokeSet
                )
            }

            if edge.direction.showsFromArrow {
                let tip = CGPoint(x: p1.x, y: p1.y).applying(exportTransform)
                let nearTip = CanvasGeometry.pointOnCurve(
                    from: p1,
                    fromSide: edge.fromSide,
                    to: p2,
                    toSide: toSide,
                    t: min(tStart + 0.05, 1)
                ).applying(exportTransform)
                drawArrowHead(
                    context: &context,
                    at: tip,
                    toward: nearTip,
                    size: arrowSize,
                    stroke: strokeSet
                )
            }
        }
    }

    private func drawArrowHead(
        context: inout GraphicsContext,
        at tip: CGPoint,
        toward origin: CGPoint,
        size: CGFloat,
        stroke: (GraphicsContext.Shading, GraphicsContext.Shading, GraphicsContext.Shading)
    ) {
        let body = CanvasGeometry.arrowHead(at: tip, toward: origin, size: size)
        let glow = CanvasGeometry.arrowHead(at: tip, toward: origin, size: size + 3)
        context.fill(glow, with: stroke.0)
        context.fill(body, with: stroke.1)
    }

    private func edgeStrokeSet(
        for edge: CanvasEdge,
        glowColor: GraphicsContext.Shading,
        bodyColor: GraphicsContext.Shading,
        coreColor: GraphicsContext.Shading
    ) -> (GraphicsContext.Shading, GraphicsContext.Shading, GraphicsContext.Shading) {
        if let custom = edge.colorHex.flatMap({ Color(hexString: $0) }) {
            return (
                GraphicsContext.Shading.color(custom.opacity(0.28)),
                GraphicsContext.Shading.color(custom),
                GraphicsContext.Shading.color(custom.opacity(0.88))
            )
        }
        return (glowColor, bodyColor, coreColor)
    }

    private func edgeMidpoint(for edge: CanvasEdge) -> CGPoint? {
        guard let from = cardIndex[edge.fromID] else { return nil }
        let p1 = CanvasGeometry.anchor(
            for: from,
            side: edge.fromSide,
            overrides: [:],
            resizeOverrides: [:]
        )
        let p2: CGPoint
        let toSide: CanvasSide?
        if let toID = edge.toID, let to = cardIndex[toID] {
            let side = edge.toSide ?? .left
            p2 = CanvasGeometry.anchor(for: to, side: side, overrides: [:], resizeOverrides: [:])
            toSide = side
        } else if let point = edge.toPoint {
            p2 = point
            toSide = nil
        } else {
            return nil
        }
        return CanvasGeometry.pointOnCurve(
            from: p1,
            fromSide: edge.fromSide,
            to: p2,
            toSide: toSide,
            t: 0.5
        )
    }

    @ViewBuilder
    private func exportCard(_ card: CanvasCard) -> some View {
        if card.kind == .image {
            exportImageCard(card)
        } else {
            exportNoteCard(card)
        }
    }

    private func exportNoteCard(_ card: CanvasCard) -> some View {
        let radius = max(2, 8 * exportScale)
        let cardColor = card.colorHex.flatMap(Color.init(hexString:))
        return ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(AppColors.noteCardBackground)
            if let cardColor {
                RoundedRectangle(cornerRadius: radius)
                    .fill(cardColor.opacity(0.08))
            }
            exportCardText(card)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(
                    cardColor?.opacity(0.8) ?? AppColors.noteCardBorder,
                    lineWidth: max(1, cardColor == nil ? exportScale : exportScale * 2)
                )
        )
    }

    @ViewBuilder
    private func exportImageCard(_ card: CanvasCard) -> some View {
        let radius = max(2, 4 * exportScale)
        let inset = max(2, 4 * exportScale)
        let cardColor = card.colorHex.flatMap(Color.init(hexString:))
        let cardWidth = max(1, card.width * exportScale)
        let cardHeight = max(1, card.height * exportScale)
        let innerWidth = max(1, cardWidth - inset * 2)
        let innerHeight = max(1, cardHeight - inset * 2)

        ZStack(alignment: .top) {
            ZStack {
                Color.clear
                #if os(macOS)
                if let image = image(for: card) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: innerWidth, height: innerHeight)
                        .clipShape(RoundedRectangle(cornerRadius: max(2, radius - 1)))
                }
                #else
                if let image = image(for: card) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: innerWidth, height: innerHeight)
                        .clipShape(RoundedRectangle(cornerRadius: max(2, radius - 1)))
                }
                #endif
            }
            .frame(width: cardWidth, height: cardHeight)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(
                        cardColor?.opacity(0.8) ?? AppColors.imageCardBorder,
                        lineWidth: max(1, cardColor == nil ? exportScale : exportScale * 2)
                    )
            )

            Text(card.title ?? CanvasStore.defaultImageTitle)
                .font(.system(size: max(7, 11 * exportScale)))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: cardWidth, alignment: .center)
                .offset(y: -(max(10, 18 * exportScale)))
        }
    }

    private func exportCardText(_ card: CanvasCard) -> some View {
        Group {
            if privacyMode {
                VStack(alignment: .leading, spacing: max(2, 6 * exportScale)) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.textMuted.opacity(0.28))
                            .frame(
                                width: index == 4 ? card.width * exportScale * 0.45 : nil,
                                height: max(2, 5 * exportScale)
                            )
                    }
                    Spacer()
                }
            } else {
                Text(card.content)
                    .font(.system(size: max(7, 13 * exportScale)))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(max(3, 8 * exportScale))
    }

    #if os(macOS)
    private func image(for card: CanvasCard) -> NSImage? {
        if let vaultURL {
            let fileURL = vaultURL.appendingPathComponent(card.content)
            if let image = NSImage(contentsOf: fileURL) {
                return image
            }
        }
        guard let data = Data(base64Encoded: card.content) else { return nil }
        return NSImage(data: data)
    }
    #else
    private func image(for card: CanvasCard) -> UIImage? {
        if let vaultURL {
            let fileURL = vaultURL.appendingPathComponent(card.content)
            if let image = UIImage(contentsOfFile: fileURL.path) {
                return image
            }
        }
        guard let data = Data(base64Encoded: card.content) else { return nil }
        return UIImage(data: data)
    }
    #endif

    static func fullCanvasBounds(
        for snapshot: CanvasDocumentSnapshot,
        padding: CGFloat = 40
    ) -> CGRect {
        let cards = Dictionary(uniqueKeysWithValues: snapshot.cards.map { ($0.id, $0) })
        var bounds = CGRect.null

        for card in snapshot.cards {
            bounds = bounds.union(CGRect(x: card.x, y: card.y, width: card.width, height: card.height))
        }

        for edge in snapshot.edges {
            guard let from = cards[edge.fromID] else { continue }
            let p1 = CanvasGeometry.anchor(
                for: from,
                side: edge.fromSide,
                overrides: [:],
                resizeOverrides: [:]
            )

            let p2: CGPoint
            let toSide: CanvasSide?
            if let toID = edge.toID, let to = cards[toID] {
                let side = edge.toSide ?? .left
                p2 = CanvasGeometry.anchor(for: to, side: side, overrides: [:], resizeOverrides: [:])
                toSide = side
            } else if let point = edge.toPoint {
                p2 = point
                toSide = nil
            } else {
                continue
            }

            for index in 0...20 {
                let t = CGFloat(index) / 20
                let point = CanvasGeometry.pointOnCurve(
                    from: p1,
                    fromSide: edge.fromSide,
                    to: p2,
                    toSide: toSide,
                    t: t
                )
                bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 0, height: 0).insetBy(dx: -24, dy: -24))
            }
        }

        guard !bounds.isNull else {
            return CGRect(x: 0, y: 0, width: 800, height: 600)
        }
        return bounds.insetBy(dx: -padding, dy: -padding)
    }

    static func effectiveScale(for bounds: CGRect, requestedScale: CGFloat) -> CGFloat {
        let safeWidth = max(1, bounds.width)
        let safeHeight = max(1, bounds.height)
        let edgeLimit = maximumEdge / max(safeWidth, safeHeight)
        let pixelLimit = sqrt(maximumPixels / (safeWidth * safeHeight))
        return max(0.01, min(requestedScale, edgeLimit, pixelLimit))
    }

    static func outputSize(for bounds: CGRect, requestedScale: CGFloat) -> CGSize {
        let scale = effectiveScale(for: bounds, requestedScale: requestedScale)
        return CGSize(
            width: max(1, (bounds.width * scale).rounded()),
            height: max(1, (bounds.height * scale).rounded())
        )
    }
}
