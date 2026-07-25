import Foundation

struct OnboardingGoalOption: Identifiable {
    let id: OnboardingGoalID
    let title: String
    let symbolName: String
}

struct OnboardingGenreOption: Identifiable {
    let id: OnboardingGenreID
    let title: String
    let symbolName: String
}

enum OnboardingConfig {
    static let goals: [OnboardingGoalOption] = [
        OnboardingGoalOption(id: .novel, title: "Writing my novel or story", symbolName: "book.closed"),
        OnboardingGoalOption(id: .webtoon, title: "Creating my webtoon or comic", symbolName: "pencil"),
        OnboardingGoalOption(id: .fanfic, title: "Writing fan fics", symbolName: "heart"),
        OnboardingGoalOption(id: .campaign, title: "Planning my TTRPG campaign", symbolName: "dice"),
        OnboardingGoalOption(id: .wiki, title: "Building a world wiki", symbolName: "globe"),
        OnboardingGoalOption(id: .lore, title: "Keeping my lore consistent", symbolName: "books.vertical"),
    ]

    static let genres: [OnboardingGenreOption] = [
        OnboardingGenreOption(id: .fantasy, title: "Fantasy", symbolName: "wand.and.stars"),
        OnboardingGenreOption(id: .romance, title: "Romance", symbolName: "heart"),
        OnboardingGenreOption(id: .scifi, title: "Sci-Fi", symbolName: "paperplane"),
        OnboardingGenreOption(id: .horror, title: "Horror", symbolName: "moon.haze"),
        OnboardingGenreOption(id: .mystery, title: "Mystery", symbolName: "magnifyingglass"),
        OnboardingGenreOption(id: .modern, title: "Modern", symbolName: "building.2"),
        OnboardingGenreOption(id: .historical, title: "Historical", symbolName: "building.columns"),
        OnboardingGenreOption(id: .dystopian, title: "Dystopian", symbolName: "eye"),
        OnboardingGenreOption(id: .cozy, title: "Cozy", symbolName: "house"),
        OnboardingGenreOption(id: .darkFantasy, title: "Dark Fantasy", symbolName: "moon.stars"),
    ]

    static let mixGenre = OnboardingGenreOption(
        id: .mix,
        title: "A mix of everything",
        symbolName: "square.grid.2x2"
    )
}
