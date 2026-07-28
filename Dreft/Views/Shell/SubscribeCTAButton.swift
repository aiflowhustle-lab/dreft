import SwiftUI

struct SubscribeCTAButton: View {
    var entitlements: EntitlementManager
    var storeManager: StoreManager
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(Self.title(entitlements: entitlements, storeManager: storeManager))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.sidebarSelection)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.title(entitlements: entitlements, storeManager: storeManager))
    }

    static func title(entitlements: EntitlementManager, storeManager: StoreManager) -> String {
        if entitlements.isReadOnly {
            return "Subscribe"
        }
        return "Start your free trial"
    }
}
