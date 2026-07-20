import SwiftUI

enum OnboardingStorage {
    static let completedKey = "hasCompletedOnboarding"
}

/// Routes between first-run onboarding and the main workspace.
struct AppRootView: View {
    @AppStorage(OnboardingStorage.completedKey) private var hasCompletedOnboarding = false
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.dark.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .dark
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
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            } else {
                WorkspaceShellView()
            }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .onChange(of: appearanceModeRaw) { _, newValue in
            let mode = AppearanceMode(rawValue: newValue) ?? .dark
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
