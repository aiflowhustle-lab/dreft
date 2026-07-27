import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum CanvasCardColors {
    /// Matches `CanvasCardSurface` note fill (base + optional tint overlay).
    static func noteSurface(colorHex: String?) -> Color {
        #if canImport(UIKit)
        return Color(noteSurfaceUIColor(colorHex: colorHex))
        #elseif canImport(AppKit)
        return Color(noteSurfaceNSColor(colorHex: colorHex))
        #else
        return AppColors.noteCardBackground
        #endif
    }

    #if canImport(UIKit)
    static func noteSurfaceUIColor(colorHex: String?) -> UIColor {
        let base = UIColor(AppColors.noteCardBackground)
        guard let hex = colorHex, !hex.isEmpty, let tintColor = Color(hexString: hex) else { return base }
        let tint = UIColor(tintColor).withAlphaComponent(0.08)
        return blend(base, with: tint) ?? base
    }

    private static func blend(_ base: UIColor, with overlay: UIColor) -> UIColor? {
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var or: CGFloat = 0, og: CGFloat = 0, ob: CGFloat = 0, oa: CGFloat = 0
        guard base.getRed(&br, green: &bg, blue: &bb, alpha: &ba),
              overlay.getRed(&or, green: &og, blue: &ob, alpha: &oa) else { return nil }
        let alpha = oa + ba * (1 - oa)
        guard alpha > 0 else { return base }
        return UIColor(
            red: (or * oa + br * ba * (1 - oa)) / alpha,
            green: (og * oa + bg * ba * (1 - oa)) / alpha,
            blue: (ob * oa + bb * ba * (1 - oa)) / alpha,
            alpha: alpha
        )
    }
    #elseif canImport(AppKit)
    static func noteSurfaceNSColor(colorHex: String?) -> NSColor {
        let base = NSColor(AppColors.noteCardBackground)
        guard let hex = colorHex, !hex.isEmpty, let tintColor = Color(hexString: hex) else { return base }
        let tint = NSColor(tintColor).withAlphaComponent(0.08)
        return tint.blended(withFraction: 0.92, of: base) ?? base
    }
    #endif
}
