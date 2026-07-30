import StoreKit
import SwiftUI

struct PaywallView: View {
    @Bindable var storeManager: StoreManager
    @Bindable var entitlements: EntitlementManager

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    @State private var errorMessage: String?
    @State private var selectedPlanID: String = StoreConstants.yearlyProductID

    private var onboardingDraft: OnboardingState {
        OnboardingPersistence.loadDraft()
    }

    private var worldName: String {
        PaywallCopy.displayWorldName(from: onboardingDraft.worldName)
    }

    private var isFreshOnboardingContext: Bool {
        onboardingDraft.worldName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && !entitlements.isReadOnly
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                paywallBackdrop

                ScrollView(.vertical, showsIndicators: false) {
                    paywallCard
                        .padding(.horizontal, 24)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .frame(minHeight: geometry.size.height, alignment: .center)
                }
            }
        }
        .task {
            OnboardingTypography.registerFontsIfNeeded()
            if storeManager.products.isEmpty {
                await storeManager.loadProducts()
            }
            if let yearly = storeManager.yearlyProduct {
                selectedPlanID = yearly.id
            }
        }
    }

    // MARK: - Layout

    private var paywallBackdrop: some View {
        AppColors.canvasBackground.opacity(0.55)
            .ignoresSafeArea()
            .onTapGesture {
                dismissPaywall()
            }
    }

    private var paywallCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(PaywallCopy.eyebrow(worldName: worldName, isFreshOnboarding: isFreshOnboardingContext))
                .font(.system(size: 11.5, weight: .medium))
                .tracking(3.5)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textSecondary)

            Text(
                PaywallCopy.headline(
                    trigger: entitlements.paywallTrigger,
                    worldName: worldName,
                    coreDesire: onboardingDraft.inferredCoreDesire(),
                    selectedGoals: onboardingDraft.selectedGoals,
                    isReadOnly: entitlements.isReadOnly,
                    context: entitlements.paywallContext
                )
            )
            .font(OnboardingTypography.display(size: headlineSize, weight: .bold))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)

            Text(PaywallCopy.subtitle(isReadOnly: entitlements.isReadOnly))
                .font(OnboardingTypography.body(size: 15.5))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)

            perksList
                .padding(.top, 28)

            if showsTrialReminder, let intro = storeManager.yearlyProduct?.subscription?.introductoryOffer {
                Text(PaywallCopy.trialReminder(introOffer: intro))
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
            }

            planPicker
                .padding(.top, showsTrialReminder ? 12 : 28)

            primaryCTA
                .padding(.top, 24)

            Text(finePrint)
                .font(.system(size: 11.5))
                .foregroundStyle(AppColors.textMuted.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            footerLinks
                .padding(.top, 20)

            if entitlements.accessState == .fullAccess {
                Button("Continue") {
                    dismissPaywall()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 28)
        .background(paywallGlassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(AppColors.border.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 30, x: 0, y: 16)
        .onTapGesture { }
    }

    @ViewBuilder
    private var paywallGlassBackground: some View {
        #if os(iOS)
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.thinMaterial)
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(AppColors.floatingChrome.opacity(0.72))
        }
        #else
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(AppColors.floatingChrome.opacity(0.92))
        #endif
    }

    private var perksList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PaywallCopy.perks, id: \.text) { perk in
                HStack(spacing: 12) {
                    Image(systemName: perk.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(AppColors.textPrimary.opacity(0.06))
                        .clipShape(Circle())

                    Text(perk.text)
                        .font(.system(size: 14.5))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                }
            }
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
                if let yearly = storeManager.yearlyProduct {
                    planCard(
                        product: yearly,
                        label: "Yearly",
                        note: PaywallCopy.yearlyNote(
                            yearlyProduct: storeManager.yearlyProduct,
                            monthlyProduct: storeManager.monthlyProduct
                        ),
                        unit: "/year",
                        badge: PaywallCopy.bestValueBadge
                    )
                }
                if let monthly = storeManager.monthlyProduct {
                    planCard(
                        product: monthly,
                        label: "Monthly",
                        note: PaywallCopy.monthlyNote(),
                        unit: "/month",
                        badge: nil
                    )
                }
            }
        }
    }

    private func planCard(
        product: Product,
        label: String,
        note: String,
        unit: String,
        badge: String?
    ) -> some View {
        let isSelected = selectedPlanID == product.id

        return Button {
            selectedPlanID = product.id
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppColors.textPrimary : AppColors.border, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(AppColors.textPrimary)
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(OnboardingColors.buttonText(for: colorScheme))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(label)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        if let badge {
                            Text(badge.uppercased())
                                .font(.system(size: 9.5, weight: .semibold))
                                .tracking(1.1)
                                .foregroundStyle(OnboardingColors.buttonText(for: colorScheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppColors.textPrimary)
                                .clipShape(Capsule())
                        }
                    }
                    Text(note)
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(OnboardingTypography.display(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? AppColors.textPrimary.opacity(0.05) : AppColors.textPrimary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppColors.textPrimary.opacity(0.55) : AppColors.border, lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.08) : .clear, radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var primaryCTA: some View {
        VStack(spacing: 10) {
            SeamlessPrimaryButton(
                title: primaryCTATitle,
                enabled: selectedProduct != nil && !storeManager.isPurchasing
            ) {
                Task { await purchaseSelectedPlan() }
            }
            .overlay {
                if storeManager.isPurchasing {
                    ProgressView()
                        .tint(OnboardingColors.buttonText(for: colorScheme))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 8) {
            Button("Terms of Service") {
                openURL(StoreConstants.termsOfUseURL)
            }
            Text("·")
                .foregroundStyle(AppColors.textMuted.opacity(0.45))
            Button("Privacy Policy") {
                openURL(StoreConstants.privacyPolicyURL)
            }
            Text("·")
                .foregroundStyle(AppColors.textMuted.opacity(0.45))
            Button {
                Task { await restorePurchases() }
            } label: {
                if storeManager.isRestoring {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Restoring…")
                    }
                } else {
                    Text("Restore Purchases")
                }
            }
            .disabled(storeManager.isRestoring || storeManager.isPurchasing)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(AppColors.textMuted.opacity(0.9))
        .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        Button {
            dismissPaywall()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 28, height: 28)
                .background(AppColors.textPrimary.opacity(0.06))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(AppColors.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .disabled(storeManager.isPurchasing)
    }

    // MARK: - Copy helpers

    private var headlineSize: CGFloat {
        #if os(iOS)
        27
        #else
        33
        #endif
    }

    private var showsTrialReminder: Bool {
        !entitlements.isReadOnly
            && selectedPlanID == StoreConstants.yearlyProductID
            && storeManager.yearlyProduct.map { storeManager.isYearlyTrialEligible($0) } == true
    }

    private var selectedProduct: Product? {
        if selectedPlanID == StoreConstants.yearlyProductID {
            return storeManager.yearlyProduct
        }
        return storeManager.monthlyProduct
    }

    private var primaryCTATitle: String {
        if storeManager.isPurchasing {
            return "Processing…"
        }
        if entitlements.isReadOnly {
            return "Subscribe"
        }
        if showsTrialReminder {
            return "Try Dreft Pro free"
        }
        return "Subscribe"
    }

    private var finePrint: String {
        guard let product = selectedProduct else {
            return PaywallCopy.subscriptionRenewalDisclaimer
        }

        if product.id == StoreConstants.yearlyProductID,
           storeManager.isYearlyTrialEligible(product),
           let intro = product.subscription?.introductoryOffer {
            let trial = PaywallCopy.introPeriodDescription(intro)
            return "\(trial), then \(product.displayPrice)/year. \(PaywallCopy.subscriptionRenewalDisclaimer)"
        }

        let unit = product.id == StoreConstants.yearlyProductID ? "year" : "month"
        return "\(product.displayPrice)/\(unit). \(PaywallCopy.subscriptionRenewalDisclaimer)"
    }

    // MARK: - Store actions

    private func dismissPaywall() {
        guard !storeManager.isPurchasing else { return }
        entitlements.dismissPaywallPresentation()
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
                if entitlements.accessState == .fullAccess {
                    dismissPaywall()
                }
            }
        } catch {
            let message = StorePurchaseError.friendlyMessage(for: error)
            if !message.isEmpty {
                errorMessage = message
            }
        }
    }

    private func restorePurchases() async {
        errorMessage = nil
        do {
            try await storeManager.restorePurchases()
            await entitlements.refresh()
            if entitlements.accessState == .fullAccess {
                dismissPaywall()
            } else if entitlements.isReadOnly {
                errorMessage = "No active subscription was found. Your vault is still available to read and export."
            } else {
                errorMessage = "No active subscription was found for this Apple ID."
            }
        } catch {
            let message = StorePurchaseError.friendlyMessage(for: error)
            if !message.isEmpty {
                errorMessage = message
            }
        }
    }
}
