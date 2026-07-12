import CoreGraphics
import SwiftUI

/// Screen-space dot grid — fixed dot size (Obsidian-style), shifts only with pan offset.
struct DotGridBackground: View {
  let panOffset: CGSize
  var dotColor: Color = AppColors.gridDotColor

  var body: some View {
    GeometryReader { geo in
      let spacing = CanvasConstants.dotSpacing
      let ox = CanvasMath.positiveModulo(panOffset.width, divisor: spacing)
      let oy = CanvasMath.positiveModulo(panOffset.height, divisor: spacing)

      Image(decorative: DotGridTile.image(for: dotColor), scale: 1, orientation: .up)
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
  private static var cache: [String: CGImage] = [:]

  static func image(for color: Color) -> CGImage {
    let key = colorKey(for: color)
    if let cached = cache[key] {
      return cached
    }
    let image = makeTile(dotColor: color)
    cache[key] = image
    return image
  }

  private static func colorKey(for color: Color) -> String {
    #if canImport(AppKit)
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
    return String(format: "%.3f-%.3f-%.3f-%.3f", ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
    #elseif canImport(UIKit)
    let ui = UIColor(color)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "%.3f-%.3f-%.3f-%.3f", r, g, b, a)
    #else
    return "default"
    #endif
  }

  private static func makeTile(dotColor: Color) -> CGImage {
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
    #if canImport(AppKit)
    context.setFillColor(NSColor(dotColor).usingColorSpace(.sRGB)?.cgColor ?? CGColor(gray: 1, alpha: 0.09))
    #elseif canImport(UIKit)
    context.setFillColor(UIColor(dotColor).cgColor)
    #endif
    let dot = CanvasConstants.dotSize
    context.fillEllipse(in: CGRect(x: 0, y: 0, width: dot, height: dot))

    guard let cgImage = context.makeImage() else {
      fatalError("DotGridTile: failed to make image")
    }
    return cgImage
  }
}

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
