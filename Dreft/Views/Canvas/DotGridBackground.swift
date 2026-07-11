import CoreGraphics
import SwiftUI

/// Screen-space dot grid — fixed dot size (Obsidian-style), shifts only with pan offset.
struct DotGridBackground: View {
  let panOffset: CGSize

  var body: some View {
    GeometryReader { geo in
      let spacing = CanvasConstants.dotSpacing
      let ox = CanvasMath.positiveModulo(panOffset.width, divisor: spacing)
      let oy = CanvasMath.positiveModulo(panOffset.height, divisor: spacing)

      Image(decorative: DotGridTile.image, scale: 1, orientation: .up)
        .resizable(resizingMode: .tile)
        .frame(width: geo.size.width + spacing, height: geo.size.height + spacing)
        .offset(x: ox, y: oy)
        .frame(width: geo.size.width, height: geo.size.height)
        .clipped()
    }
    .allowsHitTesting(false)
  }
}

private enum DotGridTile {
  static let image: CGImage = {
    let spacing = Int(CanvasConstants.dotSpacing)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: spacing,
      height: spacing,
      bitsPerComponent: 8,
      bytesPerRow: spacing * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      fatalError("DotGridTile: failed to create context")
    }

    context.clear(CGRect(x: 0, y: 0, width: spacing, height: spacing))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.09))
    let dot = CanvasConstants.dotSize
    context.fillEllipse(in: CGRect(x: 0, y: 0, width: dot, height: dot))

    guard let cgImage = context.makeImage() else {
      fatalError("DotGridTile: failed to make image")
    }
    return cgImage
  }()
}
