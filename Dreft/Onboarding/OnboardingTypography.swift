import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Typography for seamless onboarding — matches the zip prototype (`Space Grotesk` + `text-cinema`).
enum OnboardingTypography {
    static let displayFamily = "Space Grotesk"

    private static var didRegisterFont = false
    private static var usesCustomFont = true

    static func registerFontsIfNeeded() {
        guard !didRegisterFont else { return }
        didRegisterFont = true
        guard let url = Bundle.main.url(forResource: "SpaceGrotesk", withExtension: "ttf") else {
            usesCustomFont = false
            return
        }
        var error: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        usesCustomFont = resolvedFont(size: 16) != nil
    }

    static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        font(size: size, weight: weight)
    }

    static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(size: size, weight: weight)
    }

    private static func font(size: CGFloat, weight: Font.Weight) -> Font {
        registerFontsIfNeeded()
        guard usesCustomFont, resolvedFont(size: size) != nil else {
            return .system(size: size, weight: weight)
        }
        return .custom(displayFamily, size: size).weight(weight)
    }

    private static func resolvedFont(size: CGFloat) -> AnyObject? {
        #if canImport(UIKit)
        return UIFont(name: displayFamily, size: size)
        #elseif canImport(AppKit)
        return NSFont(name: displayFamily, size: size)
        #else
        return nil
        #endif
    }
}
