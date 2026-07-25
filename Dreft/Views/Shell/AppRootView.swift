import SwiftUI

/// Routes between first-run onboarding and the main workspace.
struct AppRootView: View {
    @AppStorage(OnboardingStorage.completedKey) private var hasCompletedOnboarding = false
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.light.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .light
    }

    private var shouldShowOnboarding: Bool {
        if hasCompletedOnboarding { return false }
        if let state = WorkspacePersistence.load().state, !state.vaults.isEmpty {
            return false
        }
        return true
    }

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingPresentationContainer {
                    OnboardingFlowView {
                        hasCompletedOnboarding = true
                    }
                }
            } else {
                WorkspaceShellView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.canvasBackground)
        .preferredColorScheme(appearanceMode.colorScheme)
        .onChange(of: appearanceModeRaw) { _, newValue in
            let mode = AppearanceMode(rawValue: newValue) ?? .light
            AppColors.setTheme(mode.theme)
        }
        .onAppear {
            migrateExistingUsersIfNeeded()
        }
    }

    /// Persist the skip flag for users who already had a vault before onboarding shipped.
    private func migrateExistingUsersIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        if let state = WorkspacePersistence.load().state, !state.vaults.isEmpty {
            hasCompletedOnboarding = true
        }
    }
}
