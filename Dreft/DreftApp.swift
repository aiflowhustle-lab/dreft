import SwiftUI

@main
struct DreftApp: App {
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.dark.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .dark
    }

    init() {
        // Apply the saved theme before the first frame renders — otherwise the
        // UI flashes (or sticks with) dark colors when launching in light mode.
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.dark.rawValue
        let mode = AppearanceMode(rawValue: saved) ?? .dark
        AppColors.setTheme(mode.theme)
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceShellView()
                .id(appearanceModeRaw)
                .preferredColorScheme(appearanceMode.colorScheme)
                .onChange(of: appearanceModeRaw) { _, newValue in
                    let mode = AppearanceMode(rawValue: newValue) ?? .dark
                    AppColors.setTheme(mode.theme)
                }
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
