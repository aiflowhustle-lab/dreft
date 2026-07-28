import Foundation

enum StoreConstants {
    static let subscriptionGroupName = "Dreft Pro"

    static let yearlyProductID = "com.aiflowhustle.dreft.pro.yearly"
    static let monthlyProductID = "com.aiflowhustle.dreft.pro.monthly"

    static let allProductIDs: [String] = [yearlyProductID, monthlyProductID]

    /// First App Store version that requires a subscription for new installs.
    static let firstPaidVersion = "1.2.0"

    static let privacyPolicyURL = URL(
        string: "https://lavish-birthday-3cc.notion.site/Dreft-Privacy-Policy-39e2796a245380869bb7f48509695d5e"
    )!

    static let termsOfUseURL = URL(
        string: "https://lavish-birthday-3cc.notion.site/Dreft-Terms-of-Service-3ab2796a2453808d905fdf00abb30809"
    )!

    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
}
