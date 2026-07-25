import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum OnboardingMotion {
    static let screenSlideDuration: Double = 0.275
    static let selectionHoldDuration: UInt64 = 200_000_000
    static let desireConfirmDuration: UInt64 = 700_000_000
    static let mirrorTextLead: Double = 0.15
    static let buildingStepDelay: UInt64 = 400_000_000
    static let typewriterCharacterDelayMs: Int = 34
    static let typewriterSubtitleDelayMs: Int = 180
    static let typewriterContentDelayMs: Int = 220

    static var screenSlide: Animation {
        .easeInOut(duration: screenSlideDuration)
    }

    static func selectionSlide(insertion: Edge, removal: Edge) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: insertion),
            removal: .move(edge: removal)
        )
    }

    static func playSelectionHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

extension String {
    /// Title-cases each word as the user types (onboarding world name).
    func onboardingTitleCased() -> String {
        guard !isEmpty else { return self }
        return split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard let first = word.first else { return String(word) }
                return String(first).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}
