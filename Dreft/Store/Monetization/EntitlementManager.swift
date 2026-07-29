import Foundation
import StoreKit

@MainActor
@Observable
final class EntitlementManager {
    private(set) var accessState: DreftAccessState = .locked
    private(set) var isLegacyUser = false
    private(set) var isRefreshing = false

    var showPaywall = false

    /// Create, edit, rename, move, delete, new vault, etc. Locked users may read/browse/export only.
    var canWrite: Bool { accessState == .fullAccess }

    var isLocked: Bool { accessState == .locked }

    var isReadOnly: Bool { accessState == .readOnly }

    private let storeManager: StoreManager

    init(storeManager: StoreManager) {
        self.storeManager = storeManager
        if EntitlementCache.isLegacyUser {
            isLegacyUser = true
            accessState = .fullAccess
        } else if let cached = EntitlementCache.load() {
            accessState = cached.accessState
        }
    }

    func configure() async {
        storeManager.startListening { [weak self] in
            await self?.refresh()
        }
        await storeManager.loadProducts()
        await refresh()
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        if await hydrateLegacyFromKeychainIfNeeded() {
            accessState = .fullAccess
            EntitlementCache.save(.fullAccess)
            return
        }

        if await resolveLegacyAccess() {
            accessState = .fullAccess
            EntitlementCache.save(.fullAccess)
            return
        }

        if await storeManager.hasActiveSubscription() {
            EntitlementCache.markEverSubscribed()
            accessState = .fullAccess
            EntitlementCache.save(.fullAccess)
            return
        }

        if let cached = EntitlementCache.load(), EntitlementCache.shouldFailOpen(cached) {
            accessState = .fullAccess
            return
        }

        if EntitlementCache.hasEverSubscribed {
            accessState = .readOnly
        } else {
            accessState = .locked
        }
        EntitlementCache.save(accessState)
    }

    @discardableResult
    func requireWriteAccess() -> Bool {
        guard canWrite else {
            showPaywall = true
            return false
        }
        return true
    }

    func performWrite(_ action: () -> Void) {
        guard requireWriteAccess() else { return }
        action()
    }

    func handlePurchaseCompleted() async {
        await refresh()
        if accessState == .fullAccess {
            showPaywall = false
        }
    }

    private func resolveLegacyAccess() async -> Bool {
        if EntitlementCache.isLegacyUser {
            isLegacyUser = true
            return true
        }

        do {
            let appTransaction = try await AppTransaction.shared
            switch appTransaction {
            case .verified(let transaction):
                if AppInfo.isVersion(transaction.originalAppVersion, lessThan: StoreConstants.firstPaidVersion) {
                    isLegacyUser = true
                    EntitlementCache.persistLegacyUser(true)
                    return true
                }
            case .unverified:
                break
            }
        } catch {
            let legacy = await Task.detached(priority: .utility) {
                EntitlementCache.readLegacyFromKeychain()
            }.value
            if legacy {
                isLegacyUser = true
                EntitlementCache.persistLegacyUser(true)
                return true
            }
            return EntitlementCache.isLegacyUser
        }

        return false
    }

    private func hydrateLegacyFromKeychainIfNeeded() async -> Bool {
        guard !isLegacyUser else {
            return true
        }
        let legacy = await Task.detached(priority: .utility) {
            EntitlementCache.readLegacyFromKeychain()
        }.value
        guard legacy else { return false }
        isLegacyUser = true
        EntitlementCache.persistLegacyUser(true)
        return true
    }
}
