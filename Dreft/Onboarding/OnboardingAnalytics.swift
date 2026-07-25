import Foundation

enum OnboardingAnalyticsEvent: String {
    case displayNameContinue = "onboarding_display_name_continue"
    case displayNameSkipped = "onboarding_display_name_skipped"
    case goalsContinue = "onboarding_goals_continue"
    case revealHomeComplete = "onboarding_reveal_home_complete"
    case genreSelected = "onboarding_genre_selected"
    case worldNamed = "onboarding_world_named"
    case openExistingVault = "onboarding_open_existing_vault"
    case sampleWorldStarted = "onboarding_sample_world_started"
    case vaultOpened = "onboarding_vault_opened"
    case worldReadyContinue = "onboarding_world_ready_continue"
    case buildingComplete = "onboarding_building_complete"
    case completed = "onboarding_completed"
    case guidedActionDismissed = "onboarding_guided_action_dismissed"
}

protocol OnboardingAnalyticsTracking: AnyObject {
    func track(_ event: OnboardingAnalyticsEvent, properties: [String: String])
}

extension OnboardingAnalyticsTracking {
    func track(_ event: OnboardingAnalyticsEvent) {
        track(event, properties: [:])
    }
}

final class NoOpOnboardingAnalytics: OnboardingAnalyticsTracking {
    func track(_ event: OnboardingAnalyticsEvent, properties: [String: String]) {}
}

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published private(set) var state: OnboardingState
    @Published var displayNameDraft = ""
    @Published var worldNameDraft = ""
    var usesExistingVault = false

    let analytics: OnboardingAnalyticsTracking
    let isPreview: Bool

    init(
        isPreview: Bool = false,
        analytics: OnboardingAnalyticsTracking = NoOpOnboardingAnalytics()
    ) {
        self.isPreview = isPreview
        self.analytics = analytics
        if isPreview {
            state = OnboardingState()
        } else {
            state = OnboardingPersistence.loadDraft()
            if state.hasCompletedOnboarding {
                state = OnboardingState()
            }
        }
        displayNameDraft = state.displayName ?? ""
        worldNameDraft = state.worldName ?? ""
    }

    var step: OnboardingStep { state.currentStep }

    var canGoBack: Bool {
        switch step {
        case .displayName, .revealHome, .worldReady:
            return false
        case .goals, .genre, .worldName:
            return true
        }
    }

    var resolvedDisplayName: String? {
        let trimmed = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var resolvedWorldName: String? {
        let trimmed = worldNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var showsLandscapeBackdrop: Bool {
        step != .displayName && step != .goals
    }

    var usesBrightLandscape: Bool {
        step == .worldName || step == .worldReady || (step == .genre && state.worldGenre != nil)
    }

    func persistDraft() {
        guard !isPreview else { return }
        OnboardingPersistence.saveDraft(state)
    }

    func submitDisplayName() {
        state.displayName = resolvedDisplayName
        analytics.track(.displayNameContinue, properties: ["has_name": state.displayName == nil ? "false" : "true"])
        go(to: .goals)
    }

    func skipDisplayName() {
        state.displayName = nil
        analytics.track(.displayNameSkipped)
        go(to: .goals)
    }

    func toggleGoal(_ goal: OnboardingGoalID) {
        if state.selectedGoals.contains(goal) {
            state.selectedGoals.removeAll { $0 == goal }
        } else {
            state.selectedGoals.append(goal)
        }
        persistDraft()
    }

    func advanceFromGoals() {
        guard !state.selectedGoals.isEmpty else { return }
        analytics.track(.goalsContinue, properties: [
            "goals": state.selectedGoals.map(\.rawValue).joined(separator: ","),
        ])
        go(to: .revealHome)
    }

    func advanceFromRevealHome() {
        analytics.track(.revealHomeComplete)
        go(to: .genre)
    }

    func selectGenre(_ genre: OnboardingGenreID) {
        if state.worldGenre == genre {
            state.worldGenre = nil
        } else {
            state.worldGenre = genre
            analytics.track(.genreSelected, properties: ["genre": genre.rawValue])
        }
        persistDraft()
    }

    func advanceFromGenre() {
        guard state.worldGenre != nil else { return }
        go(to: .worldName)
    }

    func submitWorldName() {
        state.worldName = resolvedWorldName
        analytics.track(.worldNamed, properties: ["has_name": state.worldName == nil ? "false" : "true"])
        persistDraft()
    }

    func trackOpenExistingVault() {
        analytics.track(.openExistingVault)
    }

    func goToWorldReady(trackBuildingComplete: Bool = false) {
        if trackBuildingComplete {
            analytics.track(.buildingComplete)
        }
        go(to: .worldReady)
    }

    func advanceFromWorldReady() {
        analytics.track(.worldReadyContinue, properties: [
            "used_existing_vault": usesExistingVault ? "true" : "false",
        ])
    }

    func completeOnboarding(fastLane: Bool) {
        state.hasCompletedOnboarding = true
        OnboardingPersistence.clearDraft()
        if !fastLane, let desire = state.inferredCoreDesire() {
            OnboardingPersistence.setPendingCoreDesire(desire)
            if desire == .finish {
                OnboardingPersistence.requestAutoPlayTimelapse()
            }
        } else {
            OnboardingPersistence.setPendingCoreDesire(nil)
        }
        analytics.track(.completed, properties: ["fast_lane": fastLane ? "true" : "false"])
    }

    func goBack() {
        guard canGoBack else { return }
        switch step {
        case .goals:
            go(to: .displayName)
        case .genre:
            go(to: .revealHome)
        case .worldName:
            go(to: .genre)
        default:
            break
        }
    }

    func returnToWorldName() {
        go(to: .worldName)
    }

    private func go(to step: OnboardingStep) {
        state.currentStep = step
        persistDraft()
    }
}
