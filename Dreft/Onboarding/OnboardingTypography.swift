import CoreText
import SwiftUI

/// Typography for seamless onboarding — matches the zip prototype (`Space Grotesk` + `text-cinema`).
enum OnboardingTypography {
    static let displayFamily = "Space Grotesk"

    private static var didRegisterFont = false

    static func registerFontsIfNeeded() {
        guard !didRegisterFont else { return }
        didRegisterFont = true
        guard let url = Bundle.main.url(forResource: "SpaceGrotesk", withExtension: "ttf") else { return }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }

    static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        registerFontsIfNeeded()
        return .custom(displayFamily, size: size).weight(weight)
    }

    static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        registerFontsIfNeeded()
        return .custom(displayFamily, size: size).weight(weight)
    }
}
