import SwiftUI

@main
struct DreftApp: App {
    var body: some Scene {
        WindowGroup {
            WorkspaceShellView()
                .preferredColorScheme(.dark)
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
