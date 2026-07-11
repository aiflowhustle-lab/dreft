import CoreGraphics

enum CanvasLayout {
  /// Scales default on-canvas image size (1.0 = full; 0.7 = 30% smaller).
  static let imageDisplayScale: CGFloat = 0.7

  /// Canvas frame size for an image — NOT raw pixel dimensions.
  /// Obsidian shows images at a reasonable on-canvas size; users resize if needed.
  static func displaySize(for pixelSize: CGSize, maxEdge: CGFloat = 560) -> CGSize {
    guard pixelSize.width > 0, pixelSize.height > 0 else {
      return scaledFallbackImageSize()
    }
    let scale = min(1, maxEdge / max(pixelSize.width, pixelSize.height))
    let raw = CGSize(
      width: max(120, (pixelSize.width * scale).rounded()),
      height: max(120, (pixelSize.height * scale).rounded())
    )
    return scaledImageSize(raw)
  }

  private static func scaledImageSize(_ size: CGSize) -> CGSize {
    let minEdge = (120 * imageDisplayScale).rounded()
    return CGSize(
      width: max(minEdge, (size.width * imageDisplayScale).rounded()),
      height: max(minEdge, (size.height * imageDisplayScale).rounded())
    )
  }

  private static func scaledFallbackImageSize() -> CGSize {
    scaledImageSize(CGSize(width: 320, height: 220))
  }

  static func topLeft(center: CGPoint, size: CGSize) -> CGPoint {
    CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
  }
}
