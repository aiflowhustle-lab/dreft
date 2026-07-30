import Foundation
import StoreKit

enum StorePurchaseError: LocalizedError {
    case productUnavailable
    case unverifiedTransaction
    case pending

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "Subscription options are unavailable right now."
        case .unverifiedTransaction:
            return "We couldn't verify your purchase. Please try again."
        case .pending:
            return "Your purchase is pending approval."
        }
    }

    static func friendlyMessage(for error: Error) -> String {
        if let storeError = error as? StorePurchaseError {
            return storeError.localizedDescription
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return "You're offline. Check your connection and try again."
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == SKErrorDomain,
           let code = SKError.Code(rawValue: nsError.code) {
            switch code {
            case .paymentCancelled:
                return ""
            case .paymentNotAllowed:
                return "In-App Purchases aren't allowed for this Apple ID. For testing, sign in with a Sandbox Account in Settings → App Store."
            case .storeProductNotAvailable:
                return "This plan isn't available in the App Store right now. Try again in a few minutes."
            case .cloudServiceNetworkConnectionFailed, .cloudServicePermissionDenied:
                return "Couldn't reach the App Store. Check your connection and try again."
            default:
                break
            }
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("not authorized") && description.contains("sandbox") {
            return "This Apple ID isn't set up for sandbox purchases. Add a Sandbox Tester in App Store Connect, then sign in under Settings → App Store → Sandbox Account."
        }
        if description.contains("unable to complete") {
            return "The purchase couldn't be completed. Confirm your Sandbox Account in Settings → App Store and try again."
        }

        return error.localizedDescription
    }
}

@MainActor
@Observable
final class StoreManager {
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var loadError: String?
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var yearlyIntroOfferEligible = false
    private(set) var activeSubscription: ActiveSubscriptionSummary?

    private var transactionListener: Task<Void, Never>?
    private var onTransactionUpdate: (() async -> Void)?

    var yearlyProduct: Product? {
        products.first { $0.id == StoreConstants.yearlyProductID }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == StoreConstants.monthlyProductID }
    }

    func startListening(onUpdate: @escaping () async -> Void) {
        onTransactionUpdate = onUpdate
        transactionListener?.cancel()
        transactionListener = Task { [weak self] in
            for await update in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                if let transaction = try? self.checkVerified(update) {
                    await transaction.finish()
                    await self.onTransactionUpdate?()
                }
            }
        }
    }

    func loadProducts() async {
        isLoadingProducts = true
        loadError = nil
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: StoreConstants.allProductIDs)
            products = StoreConstants.allProductIDs.compactMap { id in
                loaded.first { $0.id == id }
            }
            if let yearly = yearlyProduct, let subscription = yearly.subscription {
                yearlyIntroOfferEligible = await subscription.isEligibleForIntroOffer
            } else {
                yearlyIntroOfferEligible = false
            }
            if products.isEmpty {
                loadError = "No subscription plans are available right now."
            }
            await refreshActiveSubscription()
        } catch {
            loadError = StorePurchaseError.friendlyMessage(for: error)
        }
    }

    func refreshActiveSubscription() async {
        var found: ActiveSubscriptionSummary?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard StoreConstants.allProductIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }

            let planName = transaction.productID == StoreConstants.yearlyProductID ? "Yearly" : "Monthly"
            found = ActiveSubscriptionSummary(
                planName: planName,
                renewalDescription: renewalDescription(for: transaction)
            )
            break
        }

        activeSubscription = found
    }

    private func renewalDescription(for transaction: StoreKit.Transaction) -> String? {
        guard let expirationDate = transaction.expirationDate else { return nil }
        let formatted = expirationDate.formatted(date: .abbreviated, time: .omitted)
        if expirationDate > Date() {
            return "Renews \(formatted)"
        }
        return "Expired \(formatted)"
    }

    func isYearlyTrialEligible(_ product: Product) -> Bool {
        product.id == StoreConstants.yearlyProductID
            && yearlyIntroOfferEligible
            && product.subscription?.introductoryOffer != nil
    }

    @discardableResult
    func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            EntitlementCache.markEverSubscribed()
            return transaction
        case .userCancelled:
            return nil
        case .pending:
            throw StorePurchaseError.pending
        @unknown default:
            return nil
        }
    }

    func restorePurchases() async throws {
        isRestoring = true
        defer { isRestoring = false }
        try await AppStore.sync()
    }

    func hasActiveSubscription() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if StoreConstants.allProductIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                EntitlementCache.markEverSubscribed()
                return true
            }
        }
        return false
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StorePurchaseError.unverifiedTransaction
        }
    }
}
