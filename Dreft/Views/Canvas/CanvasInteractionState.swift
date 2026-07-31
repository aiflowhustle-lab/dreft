import CoreGraphics
import SwiftUI

enum CanvasInteractionMode: Equatable {
  case idle
  case canvasNavigation
  case draggingCard(String)
  case resizingCard(String)
}

/// Centralizes canvas gesture mode and in-flight card drag/resize overrides.
@Observable
final class CanvasInteractionState {
  var mode: CanvasInteractionMode = .idle
  var panAnchor = CGSize.zero
  var pinchStartZoom: CGFloat?
  var cardInteractionFrozenTransform: CanvasViewTransform?
  var cardDragOverrides: [String: CGPoint] = [:]
  var cardResizeOverrides: [String: CGRect] = [:]
  var suppressCanvasTapUntil: Date?

  var isCanvasInteracting: Bool {
    mode == .canvasNavigation
  }

  var isCardDragging: Bool {
    if case .draggingCard = mode { return true }
    return false
  }

  var isCardResizing: Bool {
    if case .resizingCard = mode { return true }
    return false
  }

  var panActive: Bool {
    mode == .canvasNavigation
  }

  func beginCanvasNavigation(anchor: CGSize) {
    mode = .canvasNavigation
    panAnchor = anchor
  }

  func endCanvasNavigation() {
    if mode == .canvasNavigation {
      mode = .idle
    }
    pinchStartZoom = nil
  }

  func beginDraggingCard(_ cardID: String, frozenTransform: CanvasViewTransform) {
    mode = .draggingCard(cardID)
    cardInteractionFrozenTransform = frozenTransform
  }

  func beginResizingCard(_ cardID: String, frozenTransform: CanvasViewTransform) {
    mode = .resizingCard(cardID)
    cardInteractionFrozenTransform = frozenTransform
  }

  func endCardDragOrResize() {
    switch mode {
    case .draggingCard, .resizingCard:
      mode = .idle
    default:
      break
    }
    cardInteractionFrozenTransform = nil
  }

  func clearCardInteraction() {
    if isCardDragging || isCardResizing {
      mode = .idle
    }
    cardInteractionFrozenTransform = nil
    cardDragOverrides.removeAll()
    cardResizeOverrides.removeAll()
  }

  func cardRenderTransform(displayTransform: CanvasViewTransform) -> CanvasViewTransform {
    if isCardDragging || isCardResizing, let frozen = cardInteractionFrozenTransform {
      return frozen
    }
    return displayTransform
  }
}
