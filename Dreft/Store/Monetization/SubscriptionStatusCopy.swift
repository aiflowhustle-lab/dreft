import Foundation

struct ActiveSubscriptionSummary: Equatable {
    let planName: String
    let renewalDescription: String?
}

enum SubscriptionStatusCopy {
    static func settingsTitle(
        accessState: DreftAccessState,
        isLegacyUser: Bool,
        activeSubscription: ActiveSubscriptionSummary?
    ) -> String {
        if isLegacyUser {
            return "Dreft Pro (Legacy)"
        }
        if let activeSubscription {
            return "Dreft Pro — \(activeSubscription.planName)"
        }
        switch accessState {
        case .fullAccess:
            return "Dreft Pro"
        case .readOnly:
            return "Dreft Pro (Expired)"
        case .locked:
            return "Upgrade to Dreft Pro"
        }
    }

    static func settingsSubtitle(
        accessState: DreftAccessState,
        isLegacyUser: Bool,
        activeSubscription: ActiveSubscriptionSummary?
    ) -> String {
        if isLegacyUser {
            return "Full access on this install — thank you for being an early Dreft writer."
        }
        if let activeSubscription {
            if let renewalDescription = activeSubscription.renewalDescription {
                return renewalDescription
            }
            return "Manage or cancel your plan in App Store Settings."
        }
        switch accessState {
        case .fullAccess:
            return "Manage your plan in App Store Settings."
        case .readOnly:
            return "Your subscription ended. Subscribe again to start writing."
        case .locked:
            return "Unlock writing on Mac and iPad with a Dreft Pro subscription."
        }
    }
}
