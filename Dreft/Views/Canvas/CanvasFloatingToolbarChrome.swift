import SwiftUI

enum CanvasFloatingToolbarChrome {
    static let pillCornerRadius: CGFloat = 14
    static let bottomPillCornerRadius: CGFloat = 12
    static let buttonSize: CGFloat = 36
    static let iconSize: CGFloat = 15
    static let pillSpacing: CGFloat = 10

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
