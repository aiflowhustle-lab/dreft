import Foundation
import StoreKit

enum PaywallCopy {
    static let proSubtitle = "Your worlds stay on your device."

    static let subscriptionRenewalDisclaimer =
        "Auto-renews until canceled in App Store Settings."

    static func trialReminder(introOffer: Product.SubscriptionOffer) -> String {
        "\(shortTrialPhrase(introOffer)) on Yearly. Cancel anytime before you're charged."
    }

    /// Short trial phrase for fine print and plan notes, e.g. "3-day free trial".
    static func shortTrialPhrase(_ offer: Product.SubscriptionOffer) -> String {
        "\(hyphenatedTrialDuration(offer)) free trial"
    }

    static func startTrialCTATitle(_ offer: Product.SubscriptionOffer) -> String {
        "Start \(hyphenatedTrialDuration(offer, titleCase: true)) Free Trial"
    }

    static func discountBadgeTitle(percent: Int) -> String {
        "SAVE \(percent)%"
    }

    struct PlanFootnoteLines: Equatable {
        let primary: String
    }

    static func planFootnoteLines(
        selectedPlanID: String,
        yearlyProduct: Product?,
        monthlyProduct: Product?,
        isYearlyTrialEligible: Bool,
        isReadOnly: Bool
    ) -> PlanFootnoteLines {
        if isReadOnly {
            return PlanFootnoteLines(primary: subscriptionRenewalDisclaimer)
        }

        let renewalNote = " Auto-renews until canceled."

        if selectedPlanID == StoreConstants.yearlyProductID, let yearly = yearlyProduct {
            let primary: String
            if isYearlyTrialEligible, let intro = yearly.subscription?.introductoryOffer {
                primary = "Free for \(hyphenatedTrialDuration(intro)), then \(yearly.displayPrice)/year."
            } else {
                primary = "\(yearly.displayPrice) per year."
            }
            return PlanFootnoteLines(primary: primary + renewalNote)
        }

        if selectedPlanID == StoreConstants.monthlyProductID, let monthly = monthlyProduct {
            return PlanFootnoteLines(primary: "\(monthly.displayPrice) per month." + renewalNote)
        }

        return PlanFootnoteLines(primary: subscriptionRenewalDisclaimer)
    }

    private static func hyphenatedTrialDuration(
        _ offer: Product.SubscriptionOffer,
        titleCase: Bool = false
    ) -> String {
        let count = offer.period.value
        switch offer.period.unit {
        case .day where count == 1:
            return titleCase ? "1-Day" : "1-day"
        case .day:
            return titleCase ? "\(count)-Day" : "\(count)-day"
        case .week where count == 1:
            return titleCase ? "1-Week" : "1-week"
        case .week:
            return titleCase ? "\(count)-Week" : "\(count)-week"
        case .month where count == 1:
            return titleCase ? "1-Month" : "1-month"
        case .month:
            return titleCase ? "\(count)-Month" : "\(count)-month"
        case .year where count == 1:
            return titleCase ? "1-Year" : "1-year"
        case .year:
            return titleCase ? "\(count)-Year" : "\(count)-year"
        @unknown default:
            return titleCase ? "Free-Trial" : "free-trial"
        }
    }

    private static let perks: [(symbol: String, text: String)] = [
        ("checkmark.seal", "Never contradict your canon."),
        ("square.stack.3d.up", "Your whole world on one canvas."),
        ("infinity", "Unlimited notes, canvases, and vaults."),
    ]

    static func orderedPerks(
        selectedGoals: [OnboardingGoalID],
        coreDesire: CoreDesire?
    ) -> [(symbol: String, text: String)] {
        let desire = coreDesire ?? OnboardingState.coreDesire(matching: selectedGoals)
        let leadingIndex: Int

        switch selectedGoals.first {
        case .lore, .webtoon:
            leadingIndex = 0
        case .wiki, .campaign:
            leadingIndex = 1
        case .novel, .fanfic:
            leadingIndex = 2
        case .none:
            switch desire {
            case .canon:
                leadingIndex = 0
            case .map:
                leadingIndex = 1
            case .finish, .own, .none:
                leadingIndex = 2
            }
        }

        let trailing = [0, 1, 2].filter { $0 != leadingIndex }
        return ([leadingIndex] + trailing).map { perks[$0] }
    }

    static func primaryCTATitle(
        isPurchasing: Bool,
        isReadOnly: Bool,
        selectedPlanID: String,
        yearlyProduct: Product?,
        monthlyProduct: Product?,
        isYearlyTrialEligible: Bool
    ) -> String {
        if isPurchasing {
            return "Processing…"
        }
        if isReadOnly {
            return "Subscribe"
        }

        if selectedPlanID == StoreConstants.yearlyProductID,
           isYearlyTrialEligible,
           let intro = yearlyProduct?.subscription?.introductoryOffer {
            return startTrialCTATitle(intro)
        }

        if selectedPlanID == StoreConstants.monthlyProductID, let monthly = monthlyProduct {
            return "Subscribe — \(monthly.displayPrice)/mo"
        }

        if selectedPlanID == StoreConstants.yearlyProductID, let yearly = yearlyProduct {
            return "Subscribe — \(yearly.displayPrice)/yr"
        }

        return "Subscribe"
    }

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

    static func subtitle(isReadOnly: Bool, rawWorldName: String?) -> String {
        if isReadOnly {
            return "Subscribe to start writing again on Mac and iPad. Your vault stays on your device — read and export anytime."
        }
        if hasPersonalizedWorldName(rawWorldName) {
            return "Keep building \(displayWorldName(from: rawWorldName))."
        }
        return proSubtitle
    }

    private static func hasPersonalizedWorldName(_ raw: String?) -> Bool {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
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
