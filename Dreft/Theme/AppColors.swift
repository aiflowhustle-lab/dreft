import SwiftUI

enum AppColors {
    static let canvasBackground = Color(hex: 0x000000)
    static let shellBackground = Color(hex: 0x000000)
    static let railBackground = Color(hex: 0x000000)
    static let tabBarBackground = Color(hex: 0x0A0A0A)
    static let toolbarBackground = Color(hex: 0x1A1A1A).opacity(0.92)
    static let floatingChrome = Color(hex: 0x262626).opacity(0.98)
    static let pillButtonFill = Color(hex: 0x1A1A1A)
    static let pillButtonText = Color(hex: 0xA78BFA)
    static let cardBackground = Color(hex: 0x252525)
    /// Note cards match the canvas surface when empty.
    static let noteCardBackground = Color(hex: 0x000000)
    static let noteCardBorder = Color(hex: 0x3A3A3A)
    static let imageCardBorder = Color.white.opacity(0.18)
    static let sidebarSelection = Color.white.opacity(0.06)
    /// Shared height for sidebar toolbar row and tab bar — keeps dividers aligned.
    static let chromeRowHeight: CGFloat = 38
    /// Top inset so icon-rail controls clear macOS traffic lights (hidden title bar).
    static let macTrafficLightInset: CGFloat = 28
    static let border = Color(hex: 0x2E2E2E)
    static let borderSubtle = Color(hex: 0x262626)
    static let textPrimary = Color(red: 0.82, green: 0.82, blue: 0.82)
    static let textSecondary = Color(red: 0.55, green: 0.55, blue: 0.55)
    static let textMuted = Color(red: 0.42, green: 0.42, blue: 0.42)
    static let noteLink = Color(hex: 0xA78BFA)
    static let noteReadableWidth: CGFloat = 700
    static let accentBlue = Color(red: 0.23, green: 0.51, blue: 0.96)
    /// Obsidian canvas selection purple
    static let selectionStroke = Color(hex: 0x7C3AED)
    /// Obsidian-style resize handles
    static let resizeCornerHandle = Color(hex: 0x6D28D9)
    static let resizeEdgeHandle = Color(hex: 0xA78BFA)
    static let handleFill = Color(red: 0.78, green: 0.78, blue: 0.78)
    static let handleStroke = Color.white.opacity(0.55)
    static let edgeOuter = Color.white.opacity(0.10)
    static let edgeStroke = Color(hex: 0x9A9A9A)
    static let edgeHighlight = Color(hex: 0xB5B5B5)
    static let edgeShadow = Color(hex: 0x2A2A2A)
    static let connectHandle = Color(red: 0.62, green: 0.62, blue: 0.62)
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
