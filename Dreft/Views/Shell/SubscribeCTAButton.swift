import SwiftUI

struct SubscribeCTAButton: View {
    var entitlements: EntitlementManager
    var storeManager: StoreManager
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(Self.title(entitlements: entitlements, storeManager: storeManager))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.selectionStroke)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.title(entitlements: entitlements, storeManager: storeManager))
    }

    static func title(entitlements: EntitlementManager, storeManager: StoreManager) -> String {
        if entitlements.isReadOnly {
            return "Subscribe"
        }
        if let yearly = storeManager.yearlyProduct,
           storeManager.isYearlyTrialEligible(yearly) {
            return "Start your free trial"
        }
        return "Subscribe"
    }
}
