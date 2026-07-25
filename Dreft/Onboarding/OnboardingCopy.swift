import Foundation

enum OnboardingCopy {
    // MARK: - Display name

    static let displayNameTitle = "What do we call you?"
    static let displayNameSubtitle = "So Dreft feels like yours."
    static let displayNameFieldLabel = "Your name"
    static let displayNamePlaceholder = "Rebecca"
    static let continueButton = "Continue"
    static let skipButton = "Skip"
    static let getStartedButton = "Get Started"
    static let backButton = "Back"

    // MARK: - Goals

    static let goalsTitle = "What are you hoping Dreft helps you with?"
    static let goalsSubtitle = "Select as many as apply."

    // MARK: - Interstitial

    static let revealHomeLine = "A new home for your worlds"
    static let interstitialSkipHint = "Tap to skip"

    // MARK: - Genre

    static let genreTitle = "What is the primary genre of your world?"

    // MARK: - World name

    static let worldNamePlaceholder = "Every great place needs a name"
    static let openExistingVault = "Already have a folder of notes? Open it instead"

    // MARK: - Vault

    static let vaultHeadline = "Ready to explore"
    static let vaultSubline = "Start with a sample world, or bring your own vault."
    static let vaultSamplePrimary = "Start with a sample world"
    static let vaultSampleSubline = "Explore canvas, notes, and graph instantly."
    static let vaultCreateSecondary = "Create new vault"
    static let vaultOpenSecondary = "Open a folder"
    static let vaultFooterHint = "Dreft keeps your worlds on this device — open Manage vaults anytime."

    // MARK: - World ready

    static let worldReadySubtitle = "Your worlds have a new home."

    static func worldReadyTitle(worldName: String?) -> String {
        let name = worldName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? worldName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : defaultWorldName
        return "\(name) is ready."
    }

    // MARK: - Building

    static let buildingFallbackWorld = "your world"
    static let buildingCheckCanvas = "Canvas"
    static let buildingCheckLore = "Lore"
    static let buildingCheckGraph = "Graph"
    static let defaultWorldName = "Lumunajia"

    static func buildingTitle(worldName: String?) -> String {
        let name = worldName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? worldName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : buildingFallbackWorld
        return "Building \(name)…"
    }

    // MARK: - Guided first action

    static func guidedMessage(for desire: CoreDesire) -> String {
        switch desire {
        case .finish:
            return "Tap the wand to replay how your world grew."
        case .canon:
            return "Type [[ in a note to link lore together."
        case .map:
            return "Drag from a card's handle to connect ideas."
        case .own:
            return "Your vault lives on your device — open Manage vaults anytime."
        }
    }
}
