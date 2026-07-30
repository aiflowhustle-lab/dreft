import Foundation

/// Why the paywall was opened — drives one-line headline overrides.
enum PaywallTrigger: Equatable {
    case onboarding
    case settings
    case readOnlyBanner
    case editBlocked
    case createBlocked
    case subscribeCTA
}
