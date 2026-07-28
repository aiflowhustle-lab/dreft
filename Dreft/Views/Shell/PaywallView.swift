import SwiftUI
import StoreKit

struct PaywallView: View {
    @Bindable var storeManager: StoreManager
    @Bindable var entitlements: EntitlementManager

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selectedPlan: PaywallPlan = .yearly
    @State private var errorMessage: String?

    private enum PaywallPlan: String, CaseIterable {
        case yearly
        case monthly
    }

    var body: some View {
        ZStack {
            AppColors.canvasBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    planPicker
                    primaryCTA
                    legalBlock
                    secondaryActions
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(AppColors.sidebarSelection)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(AppColors.borderSubtle, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(.top, 16)
            .padding(.trailing, 16)
            .disabled(storeManager.isPurchasing)
        }
        .task {
            if storeManager.products.isEmpty {
                await storeManager.loadProducts()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unlock Dreft Pro")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
            Text("Your writing, everywhere — Mac and iPad.")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    @ViewBuilder
    private var planPicker: some View {
        if storeManager.isLoadingProducts && storeManager.products.isEmpty {
            ProgressView("Loading plans…")
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if let loadError = storeManager.loadError, storeManager.products.isEmpty {
            VStack(spacing: 12) {
                Text(loadError)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await storeManager.loadProducts() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 10) {
                planCard(
                    plan: .yearly,
                    title: "Yearly",
                    priceLine: yearlyPriceLine,
                    detailLine: yearlyDetailLine,
                    highlighted: true
                )
                planCard(
                    plan: .monthly,
                    title: "Monthly",
                    priceLine: monthlyPriceLine,
                    detailLine: "Billed monthly",
                    highlighted: false
                )
            }
        }
    }

    private func planCard(
        plan: PaywallPlan,
        title: String,
        priceLine: String,
        detailLine: String,
        highlighted: Bool
    ) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textMuted)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if highlighted {
                            Text("⭐")
                        }
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    Text(priceLine)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(detailLine)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
            }
            .padding(14)
            .background(isSelected ? AppColors.sidebarSelection : AppColors.toolbarBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppColors.selectionStroke : AppColors.borderSubtle, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var primaryCTA: some View {
        VStack(spacing: 10) {
            Button {
                Task { await purchaseSelectedPlan() }
            } label: {
                HStack {
                    if storeManager.isPurchasing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(primaryCTATitle)
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(Color.white)
                .background(AppColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(selectedProduct == nil || storeManager.isPurchasing)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var legalBlock: some View {
        Text(finePrint)
            .font(.system(size: 11))
            .foregroundStyle(AppColors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var secondaryActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                Button("Restore Purchases") {
                    Task { await restorePurchases() }
                }
                .disabled(storeManager.isRestoring)

                Text("·")
                    .foregroundStyle(AppColors.textMuted)
                    .padding(.horizontal, 8)

                Button("Privacy Policy") {
                    openURL(StoreConstants.privacyPolicyURL)
                }

                Text("·")
                    .foregroundStyle(AppColors.textMuted)
                    .padding(.horizontal, 8)

                Button("Terms of Use") {
                    openURL(StoreConstants.termsOfUseURL)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(AppColors.textMuted)
            .frame(maxWidth: .infinity)

            if entitlements.accessState == .fullAccess {
                Button("Continue") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedProduct: Product? {
        switch selectedPlan {
        case .yearly: return storeManager.yearlyProduct
        case .monthly: return storeManager.monthlyProduct
        }
    }

    private var primaryCTATitle: String {
        if selectedPlan == .monthly || entitlements.isReadOnly {
            return "Subscribe"
        }
        return "Start your free trial"
    }

    private var yearlyPriceLine: String {
        guard let product = storeManager.yearlyProduct else { return "Yearly — $59.99/year" }
        return "Yearly — \(product.displayPrice)/year"
    }

    private var monthlyPriceLine: String {
        guard let product = storeManager.monthlyProduct else { return "Monthly — $7.99/month" }
        return "Monthly — \(product.displayPrice)/month"
    }

    private var yearlyDetailLine: String {
        guard let product = storeManager.yearlyProduct else {
            return "3 days free, then $59.99/year · Save 37%"
        }
        let price = product.displayPrice
        if storeManager.isYearlyTrialEligible(product),
           let intro = product.subscription?.introductoryOffer {
            let trial = introPeriodDescription(intro)
            return "\(trial), then \(price)/year · Save 37%"
        }
        return "\(price)/year · Save 37%"
    }

    private var finePrint: String {
        if selectedPlan == .yearly,
           let product = storeManager.yearlyProduct,
           storeManager.isYearlyTrialEligible(product),
           let intro = product.subscription?.introductoryOffer {
            let trial = introPeriodDescription(intro)
            return "\(trial), then \(product.displayPrice)/year. Auto-renews unless cancelled at least 24 hours before the period ends. Manage or cancel anytime in App Store Settings."
        }

        let price = selectedProduct?.displayPrice ?? "the listed price"
        let cadence = selectedPlan == .yearly ? "year" : "month"
        return "\(price)/\(cadence). Auto-renews unless cancelled at least 24 hours before the period ends. Manage or cancel anytime in App Store Settings."
    }

    private func introPeriodDescription(_ offer: Product.SubscriptionOffer) -> String {
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

    private func purchaseSelectedPlan() async {
        errorMessage = nil
        guard let product = selectedProduct else {
            errorMessage = StorePurchaseError.productUnavailable.localizedDescription
            return
        }
        await purchase(product)
    }

    private func purchase(_ product: Product) async {
        do {
            if try await storeManager.purchase(product) != nil {
                await entitlements.handlePurchaseCompleted()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restorePurchases() async {
        errorMessage = nil
        do {
            try await storeManager.restorePurchases()
            await entitlements.refresh()
            if entitlements.accessState == .fullAccess {
                dismiss()
            } else {
                errorMessage = "No active subscription was found for this Apple ID."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
