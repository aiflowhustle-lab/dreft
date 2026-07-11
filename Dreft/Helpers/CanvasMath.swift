import CoreGraphics

enum CanvasMath {
  /// Stable modulo for negative pan offsets — prevents dot-grid jitter.
  static func positiveModulo(_ value: CGFloat, divisor: CGFloat) -> CGFloat {
    guard divisor != 0 else { return 0 }
    let remainder = value.truncatingRemainder(dividingBy: divisor)
    return remainder < 0 ? remainder + divisor : remainder
  }

  static func worldTransform(zoom: CGFloat, tx: CGFloat, ty: CGFloat) -> CGAffineTransform {
    CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: tx, ty: ty)
  }
}
