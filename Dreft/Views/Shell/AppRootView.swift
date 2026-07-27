import SwiftUI

/// Routes between first-run onboarding and the main workspace.
struct AppRootView: View {
    @AppStorage(OnboardingStorage.completedKey) private var hasCompletedOnboarding = false
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.light.rawValue
    @State private var showOnboarding: Bool

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .light
    }

    init() {
        _showOnboarding = State(
            initialValue: !UserDefaults.standard.bool(forKey: OnboardingStorage.completedKey)
        )
    }

    var body: some View {
        ZStack {
            WorkspaceShellView()
                .opacity(showOnboarding ? 0 : 1)
                .allowsHitTesting(!showOnboarding)

            if showOnboarding {
                OnboardingPresentationContainer {
                    OnboardingFlowView {
                        hasCompletedOnboarding = true
                        showOnboarding = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
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
        }
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
