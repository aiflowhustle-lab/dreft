import SwiftUI

enum CanvasFloatingToolbarChrome {
    static let pillCornerRadius: CGFloat = 14
    static let bottomPillCornerRadius: CGFloat = 12
    static let buttonSize: CGFloat = 36
    static let iconSize: CGFloat = 15
    static let pillSpacing: CGFloat = 10
    /// Cap toolbar growth when zoomed in — matches Obsidian-style floating chrome.
    static let counterScaleMaxZoom: CGFloat = 1.35

    /// Counter-scale applied inside the card toolbar layer (the parent also applies `zoom`).
    /// Keeps delete/color/zoom controls the same screen size at any canvas zoom, including max zoom-out.
    static func counterScale(for zoom: CGFloat) -> CGFloat {
        let clamped = min(max(zoom, CanvasViewTransform.minZoom), counterScaleMaxZoom)
        return 1 / clamped
    }

    @ViewBuilder
    static func pill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .frame(minWidth: 46)
            .background { pillBackground(cornerRadius: pillCornerRadius) }
            .clipShape(RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)
                    .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
            )
            .shadow(color: AppColors.floatingChromeShadow, radius: 16, y: 4)
    }

    @ViewBuilder
    static func bottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background { pillBackground(cornerRadius: bottomPillCornerRadius) }
            .clipShape(RoundedRectangle(cornerRadius: bottomPillCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: bottomPillCornerRadius, style: .continuous)
                    .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
            )
            .shadow(color: AppColors.floatingChromeShadow, radius: 16, y: 4)
    }

    @ViewBuilder
    private static func pillBackground(cornerRadius: CGFloat) -> some View {
        #if os(iOS)
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppColors.floatingChrome)
        }
        #else
        if AppColors.usesMaterialChrome {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColors.floatingChrome)
            }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppColors.floatingChrome)
        }
        #endif
    }
}
