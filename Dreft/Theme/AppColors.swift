import SwiftUI
import Observation

/// Observable holder so every SwiftUI view that reads `AppColors` re-renders
/// automatically when the theme changes (no `.id()` teardown hacks needed).
@Observable
final class AppThemeState {
    static let shared = AppThemeState()
    var theme: AppTheme = .dark
}

enum AppColors {
    private static var theme: AppTheme { AppThemeState.shared.theme }

    static func setTheme(_ theme: AppTheme) {
        AppThemeState.shared.theme = theme
    }

    static var canvasBackground: Color { theme.canvasBackground }
    static var shellBackground: Color { theme.shellBackground }
    static var railBackground: Color { theme.railBackground }
    static var tabBarBackground: Color { theme.tabBarBackground }
    static var toolbarBackground: Color { theme.toolbarBackground }
    static var floatingChrome: Color { theme.floatingChrome }
    static var overlayPanel: Color { theme.overlayPanel }
    static var inputFieldBackground: Color { theme.inputFieldBackground }
    static var floatingChromeBorder: Color { theme.floatingChromeBorder }
    static var floatingChromeShadow: Color { theme.floatingChromeShadow }
    static var toolbarButtonPressed: Color { theme.toolbarButtonPressed }
    static var pillButtonFill: Color { theme.pillButtonFill }
    static var pillButtonText: Color { theme.pillButtonText }
    static var cardBackground: Color { theme.cardBackground }
    static var noteCardBackground: Color { theme.noteCardBackground }
    static var noteCardBorder: Color { theme.noteCardBorder }
    static var imageCardBorder: Color { theme.imageCardBorder }
    static var sidebarSelection: Color { theme.sidebarSelection }
    static var border: Color { theme.border }
    static var borderSubtle: Color { theme.borderSubtle }
    static var textPrimary: Color { theme.textPrimary }
    static var textSecondary: Color { theme.textSecondary }
    static var textMuted: Color { theme.textMuted }
    static var gridDotColor: Color { theme.gridDotColor }
    static var edgeOuter: Color { theme.edgeOuter }
    static var edgeStroke: Color { theme.edgeStroke }
    static var edgeHighlight: Color { theme.edgeHighlight }
    static var edgeShadow: Color { theme.edgeShadow }
    static var handleFill: Color { theme.handleFill }
    static var handleStroke: Color { theme.handleStroke }
    static var connectHandle: Color { theme.connectHandle }
    static var graphLinkColor: Color { theme.graphLinkColor }
    static var graphLinkDimmedColor: Color { theme.graphLinkDimmedColor }
    static var graphNodeColor: Color { theme.graphNodeColor }
    static var graphLabelColor: Color { theme.graphLabelColor }
    static var usesMaterialChrome: Bool { theme.usesMaterialChrome }

    /// Shared height for sidebar toolbar row and tab bar — keeps dividers aligned.
    static let chromeRowHeight: CGFloat = 38
    /// Top inset so icon-rail controls clear macOS traffic lights (hidden title bar).
    static let macTrafficLightInset: CGFloat = 36
    static let noteLink = Color(hex: 0xA78BFA)
    static let noteReadableWidth: CGFloat = 700
    static let accentBlue = Color(red: 0.23, green: 0.51, blue: 0.96)
    /// Obsidian canvas selection purple
    static let selectionStroke = Color(hex: 0x7C3AED)
    /// Obsidian-style resize handles
    static let resizeCornerHandle = Color(hex: 0x6D28D9)
    static let resizeEdgeHandle = Color(hex: 0xA78BFA)
    static let menuHighlight = Color(hex: 0x2563EB)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
