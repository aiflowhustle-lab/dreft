import Foundation

enum CreatorType: String, Codable, CaseIterable, Identifiable {
    case story
    case webtoon
    case campaign
    case notes

    var id: String { rawValue }
}

enum OnboardingGoalID: String, Codable, CaseIterable, Identifiable {
    case novel
    case webtoon
    case fanfic
    case campaign
    case wiki
    case lore

    var id: String { rawValue }
}

enum OnboardingGenreID: String, Codable, CaseIterable, Identifiable {
    case fantasy
    case romance
    case scifi
    case horror
    case mystery
    case modern
    case historical
    case dystopian
    case cozy
    case darkFantasy = "darkfantasy"
    case mix

    var id: String { rawValue }
}

enum CoreDesire: String, Codable, CaseIterable {
    case finish
    case canon
    case map
    case own
}

enum OnboardingStep: Int, Codable, CaseIterable {
    case displayName = 0
    case goals = 1
    case revealHome = 2
    case genre = 3
    case worldName = 4
    case worldReady = 5
}

struct OnboardingState: Codable, Equatable {
    var displayName: String?
    var selectedGoals: [OnboardingGoalID] = []
    var worldGenre: OnboardingGenreID?
    var worldName: String?
    var currentStep: OnboardingStep = .displayName
    var hasCompletedOnboarding: Bool = false

    static let storageKey = "onboardingDraftState"
}

enum OnboardingStorage {
    static let completedKey = "hasCompletedOnboarding"
    static let guidedActionShownKey = "onboardingGuidedActionShown"
    static let autoPlayTimelapseKey = "onboardingAutoPlayTimelapse"
    static let pendingCoreDesireKey = "onboardingPendingCoreDesire"
}

enum OnboardingPersistence {
    static func loadDraft() -> OnboardingState {
        guard let data = UserDefaults.standard.data(forKey: OnboardingState.storageKey),
              let state = try? JSONDecoder().decode(OnboardingState.self, from: data) else {
            return OnboardingState()
        }
        return state
    }

    static func saveDraft(_ state: OnboardingState) {
        guard !state.hasCompletedOnboarding else {
            UserDefaults.standard.removeObject(forKey: OnboardingState.storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: OnboardingState.storageKey)
        }
    }

    static func clearDraft() {
        UserDefaults.standard.removeObject(forKey: OnboardingState.storageKey)
    }

    static func markGuidedActionShown() {
        UserDefaults.standard.set(true, forKey: OnboardingStorage.guidedActionShownKey)
    }

    static func shouldShowGuidedAction() -> Bool {
        !UserDefaults.standard.bool(forKey: OnboardingStorage.guidedActionShownKey)
            && UserDefaults.standard.string(forKey: OnboardingStorage.pendingCoreDesireKey) != nil
    }

    static func pendingCoreDesire() -> CoreDesire? {
        guard let raw = UserDefaults.standard.string(forKey: OnboardingStorage.pendingCoreDesireKey) else {
            return nil
        }
        return CoreDesire(rawValue: raw)
    }

    static func setPendingCoreDesire(_ desire: CoreDesire?) {
        if let desire {
            UserDefaults.standard.set(desire.rawValue, forKey: OnboardingStorage.pendingCoreDesireKey)
        } else {
            UserDefaults.standard.removeObject(forKey: OnboardingStorage.pendingCoreDesireKey)
        }
    }

    static func requestAutoPlayTimelapse() {
        UserDefaults.standard.set(true, forKey: OnboardingStorage.autoPlayTimelapseKey)
    }

    static func consumeAutoPlayTimelapse() -> Bool {
        let shouldPlay = UserDefaults.standard.bool(forKey: OnboardingStorage.autoPlayTimelapseKey)
        if shouldPlay {
            UserDefaults.standard.removeObject(forKey: OnboardingStorage.autoPlayTimelapseKey)
        }
        return shouldPlay
    }
}

extension OnboardingState {
    func inferredCreatorType() -> CreatorType {
        if selectedGoals.contains(.campaign) { return .campaign }
        if selectedGoals.contains(.webtoon) { return .webtoon }
        if selectedGoals.contains(.novel) || selectedGoals.contains(.fanfic) { return .story }
        return .notes
    }

    func inferredCoreDesire() -> CoreDesire? {
        if selectedGoals.contains(.lore) { return .canon }
        if selectedGoals.contains(.wiki) { return .map }
        if selectedGoals.contains(.novel) || selectedGoals.contains(.fanfic) || selectedGoals.contains(.webtoon) {
            return .finish
        }
        if selectedGoals.contains(.campaign) { return .map }
        return .own
    }
}

extension Notification.Name {
    static let dreftShowOnboardingPreview = Notification.Name("DreftShowOnboardingPreview")
}
