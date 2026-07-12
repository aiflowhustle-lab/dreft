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

    var body: some View {
        ZStack(alignment: .topLeading) {
            AppColors.canvasBackground

            Canvas { context, size in
                drawGrid(context: &context, size: size)
                drawEdges(context: &context)
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
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(width: outputSize.width, height: outputSize.height)
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
                context.fill(dot, with: .color(Color.white.opacity(0.09)))
                y += spacing
            }
            x += spacing
        }
    }

    private func drawEdges(context: inout GraphicsContext) {
        let cards = Dictionary(uniqueKeysWithValues: snapshot.cards.map { ($0.id, $0) })
        for edge in snapshot.edges {
            guard let from = cards[edge.fromID] else { continue }
            let start = CanvasGeometry.anchor(
                for: from,
                side: edge.fromSide,
                overrides: [:],
                resizeOverrides: [:]
            )

            let end: CGPoint
            let endSide: CanvasSide?
            if let toID = edge.toID, let to = cards[toID] {
                let side = edge.toSide ?? .left
                end = CanvasGeometry.anchor(
                    for: to,
                    side: side,
                    overrides: [:],
                    resizeOverrides: [:]
                )
                endSide = side
            } else if let point = edge.toPoint {
                end = point
                endSide = nil
            } else {
                continue
            }

            let path = CanvasGeometry
                .bezierPath(from: start, fromSide: edge.fromSide, to: end, toSide: endSide)
                .applying(exportTransform)
            context.stroke(
                path,
                with: .color(AppColors.edgeStroke.opacity(0.9)),
                style: StrokeStyle(lineWidth: max(1, 2 * exportScale), lineCap: .round)
            )
        }
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

            Text(card.title ?? "Image")
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
                            .fill(Color.white.opacity(0.18))
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
    #endif

    static func fullCanvasBounds(
        for snapshot: CanvasDocumentSnapshot,
        padding: CGFloat = 40
    ) -> CGRect {
        guard let first = snapshot.cards.first else {
            return CGRect(x: 0, y: 0, width: 800, height: 600)
        }
        let firstRect = CGRect(x: first.x, y: first.y, width: first.width, height: first.height)
        let bounds = snapshot.cards.dropFirst().reduce(firstRect) { result, card in
            result.union(CGRect(x: card.x, y: card.y, width: card.width, height: card.height))
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
