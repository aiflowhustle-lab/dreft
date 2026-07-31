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

    // MARK: - Mirror (post-goals)

    static let mirrorSubline = "That's exactly what Dreft is built for."
    static let mirrorContinueButton = "Show me"

    static func mirrorHeadline(for selectedGoals: [OnboardingGoalID]) -> String {
        let priority: [(OnboardingGoalID, String)] = [
            (.lore, "So your canon never contradicts itself again."),
            (.novel, "So you finally finish the story you've been carrying."),
            (.fanfic, "So you finally finish the story you've been carrying."),
            (.webtoon, "So you ship every episode with perfect continuity."),
            (.campaign, "So you walk into every session ready."),
            (.wiki, "So you can finally see your whole world clearly."),
        ]
        for (goal, headline) in priority where selectedGoals.contains(goal) {
            return headline
        }
        return "So you can finally see your whole world clearly."
    }

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
    static let buildingStatusCanvas = "Laying out your canvas…"
    static let buildingStatusLore = "Writing your first lore…"
    static let buildingStatusGraph = "Connecting the graph…"
    static let buildingStatusFinishing = "Almost ready…"
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

    /// Starter note body seeded during onboarding from goals, genre, and world name.
    static func welcomeNoteContent(for state: OnboardingState, worldName: String) -> String {
        let world = worldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedWorld = world.isEmpty ? defaultWorldName : world
        let creator = state.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var lines: [String] = []
        if creator.isEmpty {
            lines.append("# Welcome to \(resolvedWorld)")
        } else {
            lines.append("# Welcome to \(resolvedWorld), \(creator)")
        }
        lines.append("")
        lines.append(welcomeIntroLine(for: state, worldName: resolvedWorld))
        lines.append("")
        if let genreTitle = genreTitle(for: state.worldGenre) {
            lines.append("You're building a **\(genreTitle)** world — perfect for linking characters, places, and plot on the canvas.")
            lines.append("")
        }
        lines.append("**Start here**")
        lines.append("- Open **\(resolvedWorld).canvas** to map ideas visually")
        lines.append("- Link notes with **[[wikilinks]]**")
        lines.append("- Use the graph view to see how everything connects")
        lines.append("")
        lines.append(welcomeClosingLine(for: state))
        return lines.joined(separator: "\n")
    }

    private static func genreTitle(for genre: OnboardingGenreID?) -> String? {
        guard let genre else { return nil }
        if genre == .mix { return OnboardingConfig.mixGenre.title }
        return OnboardingConfig.genres.first(where: { $0.id == genre })?.title
    }

    private static func welcomeIntroLine(for state: OnboardingState, worldName: String) -> String {
        if state.selectedGoals.contains(.lore) {
            return "Dreft is your canon board for **\(worldName)** — one place to write lore, connect it on the canvas, and keep contradictions out."
        }
        if state.selectedGoals.contains(.novel) || state.selectedGoals.contains(.fanfic) {
            return "This is home base for **\(worldName)** — draft chapters, track arcs, and see your story take shape."
        }
        if state.selectedGoals.contains(.webtoon) {
            return "Build **\(worldName)** episode by episode — cast, scenes, and continuity on one canvas."
        }
        if state.selectedGoals.contains(.campaign) {
            return "**\(worldName)** is ready for session prep — factions, locations, and hooks in one workspace."
        }
        if state.selectedGoals.contains(.wiki) {
            return "Map **\(worldName)** from a bird's-eye view — notes, links, and a canvas that grows with your wiki."
        }
        return "This is your new vault for **\(worldName)** — notes, canvas, and graph view, all on your device."
    }

    private static func welcomeClosingLine(for state: OnboardingState) -> String {
        switch state.inferredCoreDesire() {
        case .canon:
            return "When you're ready, replace this note and make \(state.worldName ?? defaultWorldName) entirely yours."
        case .finish:
            return "Small steps add up — keep writing and let the graph show your progress."
        case .map:
            return "Pan the canvas, add cards, and connect ideas until the big picture clicks."
        case .own, .none:
            return "Everything stays local in this vault — no account, no cloud required."
        }
    }
}
