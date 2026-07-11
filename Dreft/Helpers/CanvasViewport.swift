import CoreGraphics

enum CanvasViewport {
  /// Visible region in world coordinates (with padding for partially off-screen cards).
  static func worldRect(
    canvasSize: CGSize,
    transform: CanvasViewTransform,
    padding: CGFloat = 160
  ) -> CGRect {
    let z = max(transform.zoom, 0.001)
    return CGRect(
      x: (-transform.x - padding) / z,
      y: (-transform.y - padding) / z,
      width: (canvasSize.width + padding * 2) / z,
      height: (canvasSize.height + padding * 2) / z
    )
  }

  static func cardRect(_ card: CanvasCard, origin: CGPoint) -> CGRect {
    CGRect(x: origin.x, y: origin.y, width: card.width, height: card.height)
  }

  /// Card IDs that should stay mounted in the view tree.
  static func visibleCardIDs(
    cards: [CanvasCard],
    viewport: CGRect,
    positionOverrides: [String: CGPoint],
    resizeOverrides: [String: CGRect] = [:],
    selectedID: String?,
    hoverID: String?,
    spatialIndex: CanvasSpatialIndex? = nil
  ) -> Set<String> {
    var ids = Set(positionOverrides.keys)
    ids.formUnion(resizeOverrides.keys)
    if let selectedID { ids.insert(selectedID) }
    if let hoverID { ids.insert(hoverID) }

    let cardsToTest: [CanvasCard]
    if let spatialIndex, positionOverrides.isEmpty, resizeOverrides.isEmpty {
      let candidates = spatialIndex.candidateIDs(intersecting: viewport)
      cardsToTest = cards.filter { candidates.contains($0.id) }
    } else {
      cardsToTest = cards
    }

    for card in cardsToTest {
      let rect = CanvasGeometry.cardRect(card, overrides: positionOverrides, resizeOverrides: resizeOverrides)
      if rect.intersects(viewport) {
        ids.insert(card.id)
      }
    }
    return ids
  }

  static func edgeIntersectsViewport(
    _ edge: CanvasEdge,
    cardIndex: [String: CanvasCard],
    positionOverrides: [String: CGPoint],
    resizeOverrides: [String: CGRect] = [:],
    viewport: CGRect
  ) -> Bool {
    guard let from = cardIndex[edge.fromID] else { return false }
    if CanvasGeometry.cardRect(from, overrides: positionOverrides, resizeOverrides: resizeOverrides).intersects(viewport) { return true }

    if let toID = edge.toID, let to = cardIndex[toID] {
      return CanvasGeometry.cardRect(to, overrides: positionOverrides, resizeOverrides: resizeOverrides).intersects(viewport)
    }
    if let point = edge.toPoint {
      return viewport.insetBy(dx: -240, dy: -240).contains(point)
    }
    return false
  }
}
