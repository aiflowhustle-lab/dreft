import Foundation
import StoreKit

enum PaywallCopy {
    static let proSubtitle = "Your worlds stay on your device."

    static let subscriptionRenewalDisclaimer =
        "Auto-renews until canceled in App Store Settings."

    static func trialReminder(introOffer: Product.SubscriptionOffer) -> String {
        "\(shortTrialPhrase(introOffer)) on Yearly. Cancel anytime before you're charged."
    }

    /// Short trial phrase for fine print and plan notes, e.g. "3 days free trial".
    static func shortTrialPhrase(_ offer: Product.SubscriptionOffer) -> String {
        "\(trialDurationPhrase(offer)) free trial"
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


    static let perks: [(symbol: String, text: String)] = [
        ("checkmark.seal", "Never contradict your canon."),
        ("square.stack.3d.up", "Your whole world on one canvas."),
        ("infinity", "Unlimited notes, canvases, and vaults."),
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
        isTrialEligible: Bool,
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
            return "Create without limits."
        case .subscribeCTA:
            return isTrialEligible ? "Try Dreft Pro free" : "Create without limits."
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

    static func yearlyDiscountPercent(yearlyProduct: Product?, monthlyProduct: Product?) -> Int? {
        guard let yearly = yearlyProduct, let monthly = monthlyProduct else { return 37 }

        let annualMonthly = monthly.price * 12
        guard annualMonthly > yearly.price else { return nil }

        let savings = annualMonthly - yearly.price
        let ratio = savings / annualMonthly
        var percent = ratio * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &percent, 0, .down)
        let value = (rounded as NSDecimalNumber).intValue
        return value > 0 ? value : nil
    }

    static func yearlyPerMonthNote(yearlyProduct: Product?) -> String {
        guard let yearly = yearlyProduct else { return "$5.00/mo" }
        let perMonth = yearly.price / 12
        return "\(perMonth.formatted(yearly.priceFormatStyle))/mo"
    }

    static func yearlyNote(
        yearlyProduct: Product?,
        includesTrial: Bool,
        introOffer: Product.SubscriptionOffer?
    ) -> String {
        let perMonth = yearlyPerMonthNote(yearlyProduct: yearlyProduct)
        if includesTrial, let introOffer {
            return "\(perMonth) · \(shortTrialPhrase(introOffer))"
        }
        return perMonth
    }
}
