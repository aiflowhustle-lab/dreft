import SwiftUI

/// Onboarding-only palette — black accent (inverts in dark mode for contrast).
enum OnboardingColors {
    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }

    static func buttonFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }

    static func buttonText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }

    static func accentMuted(for scheme: ColorScheme) -> Color {
        accent(for: scheme).opacity(0.22)
    }
}
