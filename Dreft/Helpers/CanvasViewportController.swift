import CoreGraphics
import Foundation
import Observation

struct CanvasViewportEnvironment {
  var canvasSize: CGSize
  var displayTransform: CanvasViewTransform
  var cards: [CanvasCard]
  var edges: [CanvasEdge]
  var cardIndex: [String: CanvasCard]
  var cardDragOverrides: [String: CGPoint]
  var cardResizeOverrides: [String: CGRect]
  var selectedCardID: String?
  var hoverCardID: String?
  var focusCardID: String?
  var selectedEdgeID: String?
  var editingEdgeLabelID: String?
  var storeEditingEdgeID: String?
  var pendingEdgeInteractionID: String?
  var isCardDragging: Bool
  var isCardResizing: Bool
  var isCanvasInteracting: Bool
  var timelapseActive: Bool
  var spatialIndex: CanvasSpatialIndex?
}

/// Sticky viewport culling — expands while navigating, trims when settled.
@Observable
final class CanvasViewportController {
  private(set) var mountedCardIDs: Set<String> = []
  private(set) var mountedEdgeIDs: Set<String> = []
  private var cullingDebounceTask: Task<Void, Never>?

  func replaceMountedContent(using environment: CanvasViewportEnvironment) {
    guard !environment.timelapseActive else { return }
    cullingDebounceTask?.cancel()
    mountedCardIDs = computeVisibleCardIDs(using: environment)
    mountedEdgeIDs = computeVisibleEdgeIDs(using: environment)
  }

  func expandMountedContent(using environment: CanvasViewportEnvironment) {
    guard !environment.timelapseActive else { return }
    mountedCardIDs.formUnion(computeVisibleCardIDs(using: environment))
    mountedEdgeIDs.formUnion(computeVisibleEdgeIDs(using: environment))
  }

  func handleViewportChanged(using environment: CanvasViewportEnvironment) {
    guard !environment.timelapseActive else { return }
    #if os(iOS)
    let isKeyboardAdjustingViewport = environment.focusCardID != nil
    #else
    let isKeyboardAdjustingViewport = false
    #endif
    if environment.isCanvasInteracting
      || environment.isCardResizing
      || environment.isCardDragging
      || isKeyboardAdjustingViewport {
      scheduleMountedContentExpansion(using: environment)
    } else {
      replaceMountedContent(using: environment)
    }
  }

  func scheduleMountedContentExpansion(using environment: CanvasViewportEnvironment) {
    cullingDebounceTask?.cancel()
    cullingDebounceTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(CanvasConstants.cullingDebounceMs))
      guard !Task.isCancelled else { return }
      expandMountedContent(using: environment)
    }
  }

  func mountedCards(
    sourceCards: [CanvasCard],
    using environment: CanvasViewportEnvironment
  ) -> [CanvasCard] {
    if environment.timelapseActive {
      return sourceCards
    }
    let ids = mountedCardIDs.isEmpty
      ? computeVisibleCardIDs(using: environment)
      : mountedCardIDs
    return sourceCards.filter { ids.contains($0.id) }
  }

  func mountedEdges(
    sourceEdges: [CanvasEdge],
    using environment: CanvasViewportEnvironment
  ) -> [CanvasEdge] {
    if environment.timelapseActive {
      return sourceEdges
    }
    let ids = mountedEdgeIDs.isEmpty
      ? computeVisibleEdgeIDs(using: environment)
      : mountedEdgeIDs
    return sourceEdges.filter { ids.contains($0.id) }
  }

  func computeVisibleCardIDs(using environment: CanvasViewportEnvironment, padding: CGFloat? = nil) -> Set<String> {
    let pad = padding ?? viewportPadding(isCardDragging: environment.isCardDragging, isCardResizing: environment.isCardResizing)
    return CanvasViewport.visibleCardIDs(
      cards: environment.cards,
      viewport: worldRect(canvasSize: environment.canvasSize, transform: environment.displayTransform, padding: pad),
      positionOverrides: environment.cardDragOverrides,
      resizeOverrides: environment.cardResizeOverrides,
      selectedID: environment.selectedCardID,
      hoverID: environment.hoverCardID,
      focusID: environment.focusCardID,
      spatialIndex: environment.spatialIndex
    )
  }

  func computeVisibleEdgeIDs(using environment: CanvasViewportEnvironment, padding: CGFloat? = nil) -> Set<String> {
    let pad = padding ?? viewportPadding(isCardDragging: environment.isCardDragging, isCardResizing: environment.isCardResizing)
    return CanvasViewport.visibleEdgeIDs(
      edges: environment.edges,
      cardIndex: environment.cardIndex,
      viewport: worldRect(canvasSize: environment.canvasSize, transform: environment.displayTransform, padding: pad),
      positionOverrides: environment.cardDragOverrides,
      resizeOverrides: environment.cardResizeOverrides,
      selectedID: environment.selectedEdgeID,
      editingID: environment.editingEdgeLabelID ?? environment.storeEditingEdgeID,
      pendingInteractionID: environment.pendingEdgeInteractionID
    )
  }

  private func viewportPadding(isCardDragging: Bool, isCardResizing: Bool) -> CGFloat {
    if isCardResizing || isCardDragging {
      return CanvasConstants.interactionViewportPadding
    }
    return CanvasConstants.viewportPadding
  }

  private func worldRect(canvasSize: CGSize, transform: CanvasViewTransform, padding: CGFloat) -> CGRect {
    CanvasViewport.worldRect(canvasSize: canvasSize, transform: transform, padding: padding)
  }
}
