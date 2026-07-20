import SwiftUI

@main
struct DreftApp: App {
    init() {
        // Apply the saved theme before the first frame renders — otherwise the
        // UI flashes (or sticks with) dark colors when launching in light mode.
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.dark.rawValue
        let mode = AppearanceMode(rawValue: saved) ?? .dark
        AppColors.setTheme(mode.theme)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Image to Canvas") {
                    NotificationCenter.default.post(name: .openImagePanel, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}
