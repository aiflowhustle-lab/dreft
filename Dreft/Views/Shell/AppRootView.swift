import SwiftUI

/// Routes between first-run onboarding and the main workspace.
struct AppRootView: View {
    @AppStorage(OnboardingStorage.completedKey) private var hasCompletedOnboarding = false
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.light.rawValue
    @State private var showOnboarding: Bool
    @State private var storeManager = StoreManager()
    @State private var entitlements: EntitlementManager
    @Environment(\.scenePhase) private var scenePhase

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .light
    }

    init() {
        let storeManager = StoreManager()
        _storeManager = State(initialValue: storeManager)
        _entitlements = State(initialValue: EntitlementManager(storeManager: storeManager))
        _showOnboarding = State(
            initialValue: !UserDefaults.standard.bool(forKey: OnboardingStorage.completedKey)
        )
    }

    var body: some View {
        ZStack {
            if hasCompletedOnboarding {
                WorkspaceShellView(
                    entitlements: entitlements,
                    storeManager: storeManager
                )
            }

            if showOnboarding {
                OnboardingPresentationContainer {
                    OnboardingFlowView {
                        finishOnboarding()
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }

            if entitlements.showPaywall {
                PaywallView(storeManager: storeManager, entitlements: entitlements)
                    .zIndex(15)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.canvasBackground)
        .preferredColorScheme(appearanceMode.colorScheme)
        .onChange(of: appearanceModeRaw) { _, newValue in
            applyAppearanceMode(rawValue: newValue)
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed {
                showOnboarding = false
            }
        }
        .task {
            migrateExistingUsersIfNeeded()
            applyAppearanceMode(rawValue: appearanceModeRaw)
            if !hasCompletedOnboarding,
               let state = WorkspacePersistence.load().state,
               !state.vaults.isEmpty {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
            await entitlements.configure()
            await storeManager.loadProducts()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await entitlements.refresh() }
            }
        }
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
        showOnboarding = false
    }

    private func applyAppearanceMode(rawValue: String) {
        let mode = AppearanceMode(rawValue: rawValue) ?? .light
        AppColors.setTheme(mode.theme)
    }

    /// Persist the skip flag for users who already had a vault before onboarding shipped.
    private func migrateExistingUsersIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        if let state = WorkspacePersistence.load().state, !state.vaults.isEmpty {
            hasCompletedOnboarding = true
        }
    }
}
