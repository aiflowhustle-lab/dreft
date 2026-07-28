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
        } catch {
            loadError = error.localizedDescription
        }
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
