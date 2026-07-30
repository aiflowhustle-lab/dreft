import Foundation
import StoreKit

enum PaywallCopy {
    static let proSubtitle = "Dreft Pro — your writing, everywhere. Local-first, no account needed."

    static let subscriptionRenewalDisclaimer =
        "Payment will be charged to your Apple ID. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. Manage and cancel in App Store Settings."

    static func trialReminder(introOffer: Product.SubscriptionOffer) -> String {
        "Try everything free for \(trialDurationPhrase(introOffer)). Cancel anytime before you're charged."
    }

    static func introPeriodDescription(_ offer: Product.SubscriptionOffer) -> String {
        let count = offer.period.value
        switch offer.period.unit {
        case .day where count == 1: return "1-day free trial"
        case .day: return "\(count)-day free trial"
        case .week where count == 1: return "1-week free trial"
        case .week: return "\(count)-week free trial"
        case .month where count == 1: return "1-month free trial"
        case .month: return "\(count)-month free trial"
        case .year where count == 1: return "1-year free trial"
        case .year: return "\(count)-year free trial"
        @unknown default: return "Free trial"
        }
    }

    private static func trialDurationPhrase(_ offer: Product.SubscriptionOffer) -> String {
        let count = offer.period.value
        switch offer.period.unit {
        case .day where count == 1: return "1 day"
        case .day: return "\(count) days"
        case .week where count == 1: return "1 week"
        case .week: return "\(count) weeks"
        case .month where count == 1: return "1 month"
        case .month: return "\(count) months"
        case .year where count == 1: return "1 year"
        case .year: return "\(count) years"
        @unknown default: return "the trial period"
        }
    }

    static let bestValueBadge = "Best value"

    static let perks: [(symbol: String, text: String)] = [
        ("infinity", "Never contradict your canon."),
        ("square.stack.3d.up", "Your whole world on one canvas."),
        ("sparkles", "Local-first. Your worlds stay yours."),
    ]

    static func eyebrow(worldName: String, isFreshOnboarding: Bool) -> String {
        if isFreshOnboarding {
            return "\(worldName) is ready"
        }
        return "Dreft Pro"
    }

    static func headline(
        trigger: PaywallTrigger,
        worldName: String,
        coreDesire: CoreDesire?,
        selectedGoals: [OnboardingGoalID],
        isReadOnly: Bool,
        context: String?
    ) -> String {
        if isReadOnly {
            return "Resume Dreft Pro"
        }

        if trigger == .editBlocked,
           let context,
           !context.isEmpty {
            return "Unlock editing in \(context)."
        }

        switch trigger {
        case .createBlocked:
            return "Create freely in \(worldName)."
        case .settings:
            return "Upgrade to Dreft Pro"
        case .subscribeCTA:
            return "Try Dreft Pro free"
        case .readOnlyBanner:
            return "Resume Dreft Pro"
        case .editBlocked:
            return "Unlock writing in \(worldName)."
        case .onboarding:
            break
        }

        if selectedGoals.contains(.webtoon) {
            return "Ship every episode. Perfect continuity."
        }
        if selectedGoals.contains(.campaign) {
            return "Never walk into a session unprepared."
        }

        switch coreDesire {
        case .canon:
            return "Keep \(worldName)'s canon perfect, forever."
        case .finish:
            return "Finish \(worldName). For real this time."
        case .map:
            return "See all of \(worldName), clearly."
        case .own, .none:
            return "See all of \(worldName), clearly."
        }
    }

    static func subtitle(isReadOnly: Bool) -> String {
        if isReadOnly {
            return "Subscribe to start writing again on Mac and iPad. Your vault stays on your device — read and export anytime."
        }
        return proSubtitle
    }

    static func readingFooter(worldName: String) -> String {
        "You can keep reading \(worldName) anytime — Pro unlocks editing."
    }

    static func displayWorldName(from raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "your world" }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }

    static func monthlyNote() -> String {
        "Billed monthly"
    }

    static func yearlyNote(yearlyProduct: Product?, monthlyProduct: Product?) -> String {
        guard let yearly = yearlyProduct else {
            return "$5.00/mo · save $36/yr"
        }

        let perMonth = yearly.price / 12
        let perMonthText = perMonth.formatted(yearly.priceFormatStyle)

        if let monthly = monthlyProduct {
            let savings = (monthly.price * 12) - yearly.price
            if savings > 0 {
                let savingsText = savings.formatted(yearly.priceFormatStyle)
                return "\(perMonthText)/mo · save \(savingsText)/yr"
            }
        }

        return "\(perMonthText)/mo · save 37%"
    }
}
