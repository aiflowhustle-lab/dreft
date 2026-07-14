import SwiftUI

struct AppTheme: Equatable {
    let canvasBackground: Color
    let shellBackground: Color
    let railBackground: Color
    let tabBarBackground: Color
    let toolbarBackground: Color
    let floatingChrome: Color
    let floatingChromeBorder: Color
    let floatingChromeShadow: Color
    let overlayPanel: Color
    let inputFieldBackground: Color
    let toolbarButtonPressed: Color
    let pillButtonFill: Color
    let pillButtonText: Color
    let cardBackground: Color
    let noteCardBackground: Color
    let noteCardBorder: Color
    let imageCardBorder: Color
    let sidebarSelection: Color
    let border: Color
    let borderSubtle: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let gridDotColor: Color
    let edgeOuter: Color
    let edgeStroke: Color
    let edgeHighlight: Color
    let edgeShadow: Color
    let handleFill: Color
    let handleStroke: Color
    let connectHandle: Color
    let graphLinkColor: Color
    let graphLinkDimmedColor: Color
    let graphNodeColor: Color
    let graphLabelColor: Color
    let usesMaterialChrome: Bool

    static let dark = AppTheme(
        canvasBackground: Color(hex: 0x000000),
        shellBackground: Color(hex: 0x000000),
        railBackground: Color(hex: 0x000000),
        tabBarBackground: Color(hex: 0x0A0A0A),
        toolbarBackground: Color(hex: 0x1A1A1A).opacity(0.92),
        floatingChrome: Color(hex: 0x2B2B2B).opacity(0.72),
        floatingChromeBorder: Color.white.opacity(0.12),
        floatingChromeShadow: Color.black.opacity(0.45),
        overlayPanel: Color(hex: 0x161616),
        inputFieldBackground: Color.white.opacity(0.08),
        toolbarButtonPressed: Color.white.opacity(0.08),
        pillButtonFill: Color(hex: 0x1A1A1A),
        pillButtonText: Color(hex: 0xA78BFA),
        cardBackground: Color(hex: 0x252525),
        noteCardBackground: Color(hex: 0x000000),
        noteCardBorder: Color(hex: 0x3A3A3A),
        imageCardBorder: Color.white.opacity(0.18),
        sidebarSelection: Color.white.opacity(0.06),
        border: Color(hex: 0x2E2E2E),
        borderSubtle: Color(hex: 0x262626),
        textPrimary: Color(red: 0.82, green: 0.82, blue: 0.82),
        textSecondary: Color(red: 0.55, green: 0.55, blue: 0.55),
        textMuted: Color(red: 0.42, green: 0.42, blue: 0.42),
        gridDotColor: Color.white.opacity(0.09),
        edgeOuter: Color.white.opacity(0.10),
        edgeStroke: Color(hex: 0x9A9A9A),
        edgeHighlight: Color(hex: 0xB5B5B5),
        edgeShadow: Color(hex: 0x2A2A2A),
        handleFill: Color(red: 0.78, green: 0.78, blue: 0.78),
        handleStroke: Color.white.opacity(0.55),
        connectHandle: Color(red: 0.62, green: 0.62, blue: 0.62),
        graphLinkColor: Color(hex: 0xB0B0B0).opacity(0.72),
        graphLinkDimmedColor: Color(hex: 0x888888).opacity(0.35),
        graphNodeColor: Color.white.opacity(0.92),
        graphLabelColor: Color.white.opacity(0.88),
        usesMaterialChrome: false
    )

    static let light = AppTheme(
        canvasBackground: Color(hex: 0xFFFFFF),
        shellBackground: Color(hex: 0xF3F3F3),
        railBackground: Color(hex: 0xF3F3F3),
        // Slightly cooler than canvas white so the active tab reads as elevated.
        tabBarBackground: Color(hex: 0xF0F0F0),
        toolbarBackground: Color.white.opacity(0.92),
        floatingChrome: Color.white,
        floatingChromeBorder: Color.black.opacity(0.08),
        floatingChromeShadow: Color.black.opacity(0.12),
        overlayPanel: Color(hex: 0xF7F7F7),
        inputFieldBackground: Color.white,
        toolbarButtonPressed: Color.black.opacity(0.06),
        pillButtonFill: Color(hex: 0xFFFFFF),
        pillButtonText: Color(hex: 0x7C3AED),
        cardBackground: Color(hex: 0xF5F5F5),
        noteCardBackground: Color(hex: 0xFFFFFF),
        noteCardBorder: Color(hex: 0xD4D4D4),
        imageCardBorder: Color.black.opacity(0.12),
        sidebarSelection: Color.black.opacity(0.06),
        border: Color(hex: 0xE0E0E0),
        borderSubtle: Color(hex: 0xEBEBEB),
        textPrimary: Color(red: 0.22, green: 0.22, blue: 0.22),
        textSecondary: Color(red: 0.45, green: 0.45, blue: 0.45),
        textMuted: Color(red: 0.62, green: 0.62, blue: 0.62),
        gridDotColor: Color.black.opacity(0.12),
        edgeOuter: Color.black.opacity(0.08),
        edgeStroke: Color(hex: 0x7A7A7A),
        edgeHighlight: Color(hex: 0x5A5A5A),
        edgeShadow: Color(hex: 0xD0D0D0),
        handleFill: Color(red: 0.35, green: 0.35, blue: 0.35),
        handleStroke: Color.black.opacity(0.35),
        connectHandle: Color(red: 0.45, green: 0.45, blue: 0.45),
        graphLinkColor: Color(hex: 0x2A2A2A).opacity(0.72),
        graphLinkDimmedColor: Color(hex: 0x666666).opacity(0.28),
        graphNodeColor: Color(hex: 0x2A2A2A),
        graphLabelColor: Color(hex: 0x222222),
        usesMaterialChrome: false
    )
}
