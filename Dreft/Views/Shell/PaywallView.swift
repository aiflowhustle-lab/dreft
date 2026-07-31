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
            normalizePlanSelection()
        }
        .onChange(of: storeManager.products) { _, _ in
            normalizePlanSelection()
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

            Text(paywallHeadline)
            .font(OnboardingTypography.display(size: headlineSize, weight: .bold))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)

            Text(PaywallCopy.subtitle(isReadOnly: entitlements.isReadOnly, rawWorldName: onboardingDraft.worldName))
                .font(OnboardingTypography.body(size: 15.5))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)

            perksList
                .padding(.top, 28)

            planPicker
                .padding(.top, 28)

            primaryCTA
                .padding(.top, 24)

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

    private var personalizedPerks: [(symbol: String, text: String)] {
        PaywallCopy.orderedPerks(
            selectedGoals: onboardingDraft.selectedGoals,
            coreDesire: onboardingDraft.inferredCoreDesire()
        )
    }

    private var perksList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(personalizedPerks, id: \.text) { perk in
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
                            includesTrial: isYearlyTrialEligible,
                            introOffer: yearly.subscription?.introductoryOffer
                        ),
                        unit: "/year",
                        discountPercent: PaywallCopy.yearlyDiscountPercent(
                            yearlyProduct: storeManager.yearlyProduct,
                            monthlyProduct: storeManager.monthlyProduct
                        )
                    )
                    .padding(.top, 6)
                }
                if let monthly = storeManager.monthlyProduct {
                    planCard(
                        product: monthly,
                        label: "Monthly",
                        note: PaywallCopy.monthlyNote(),
                        unit: "/month",
                        discountPercent: nil
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
        discountPercent: Int?
    ) -> some View {
        let isSelected = selectedPlanID == product.id
        let cardCornerRadius: CGFloat = 16
        let accent = paywallAccent

        return Button {
            selectedPlanID = product.id
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? accent : AppColors.border, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(paywallAccentForeground)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
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
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(AppColors.textPrimary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(isSelected ? accent : AppColors.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if let discountPercent {
                Text(PaywallCopy.discountBadgeTitle(percent: discountPercent))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(paywallAccentForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent)
                    .clipShape(Capsule())
                    .offset(x: -12, y: -9)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var primaryCTA: some View {
        VStack(spacing: 10) {
            SeamlessPrimaryButton(
                title: primaryCTATitle,
                enabled: selectedProduct != nil && !storeManager.isPurchasing,
                fillColor: paywallCTAFill,
                textColor: paywallCTAText
            ) {
                Task { await purchaseSelectedPlan() }
            }
            .overlay {
                if storeManager.isPurchasing {
                    ProgressView()
                        .tint(paywallCTAText)
                }
            }

            subscriptionDisclosure

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var subscriptionDisclosure: some View {
        Text(planFootnoteText)
            .font(.caption2)
            .foregroundStyle(AppColors.textMuted.opacity(0.75))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(planFootnoteText)
    }

    private var planFootnoteText: String {
        PaywallCopy.planFootnoteLines(
            selectedPlanID: selectedPlanID,
            yearlyProduct: storeManager.yearlyProduct,
            monthlyProduct: storeManager.monthlyProduct,
            isYearlyTrialEligible: isYearlyTrialEligible,
            isReadOnly: entitlements.isReadOnly
        ).primary
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
        .font(.caption2)
        .tracking(0.4)
        .foregroundStyle(AppColors.textMuted.opacity(0.62))
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

    private var paywallHeadline: String {
        let base = PaywallCopy.headline(
            trigger: entitlements.paywallTrigger,
            worldName: worldName,
            coreDesire: onboardingDraft.inferredCoreDesire(),
            selectedGoals: onboardingDraft.selectedGoals,
            isReadOnly: entitlements.isReadOnly,
            isTrialEligible: showsTrialReminder,
            context: entitlements.paywallContext
        )
        return base
    }

    private var isYearlyTrialEligible: Bool {
        storeManager.yearlyProduct.map { storeManager.isYearlyTrialEligible($0) } == true
    }

    private var showsTrialReminder: Bool {
        !entitlements.isReadOnly
            && selectedPlanID == StoreConstants.yearlyProductID
            && isYearlyTrialEligible
    }

    private var selectedProduct: Product? {
        if selectedPlanID == StoreConstants.yearlyProductID {
            return storeManager.yearlyProduct
        }
        return storeManager.monthlyProduct
    }

    /// Keeps the selection on a product that actually loaded (e.g. yearly missing, monthly present).
    private func normalizePlanSelection() {
        if selectedProduct == nil,
           let available = storeManager.yearlyProduct ?? storeManager.monthlyProduct {
            selectedPlanID = available.id
        }
    }

    private var primaryCTATitle: String {
        PaywallCopy.primaryCTATitle(
            isPurchasing: storeManager.isPurchasing,
            isReadOnly: entitlements.isReadOnly,
            selectedPlanID: selectedPlanID,
            yearlyProduct: storeManager.yearlyProduct,
            monthlyProduct: storeManager.monthlyProduct,
            isYearlyTrialEligible: showsTrialReminder
        )
    }

    // MARK: - Store actions

    private var paywallAccent: Color {
        colorScheme == .dark ? .white : .black
    }

    private var paywallAccentForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var paywallCTAFill: Color {
        colorScheme == .dark ? .white : .black
    }

    private var paywallCTAText: Color {
        colorScheme == .dark ? .black : .white
    }

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
