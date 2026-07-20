import SwiftUI

/// Shared sizing for the bottom-center canvas creation bar (Mac + iPad).
enum CanvasBottomToolbarMetrics {
    static let iconSize: CGFloat = 21
    static let buttonWidth: CGFloat = 50
    static let buttonHeight: CGFloat = 48
    static let buttonSpacing: CGFloat = 3
    static let barCornerRadius: CGFloat = 14
    static let buttonCornerRadius: CGFloat = 8
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 7
    static let bottomInset: CGFloat = 18
}

/// Obsidian-style bottom creation toolbar — a rounded bar with three document icons.
struct CanvasIPadBottomToolbar: View {
    var imageSystemName: String = "doc.circle"
    var safeAreaBottom: CGFloat = 0
    var onAddCard: () -> Void
    var onVaultNote: () -> Void
    var onAddImage: () -> Void

    private var bottomPadding: CGFloat {
        max(CanvasBottomToolbarMetrics.bottomInset, safeAreaBottom + 6)
    }

    var body: some View {
        HStack(spacing: CanvasBottomToolbarMetrics.buttonSpacing) {
            bottomButton("doc", tip: "Add card", action: onAddCard)
            bottomButton("doc.text", tip: "Vault note", action: onVaultNote)
            bottomButton(imageSystemName, tip: "Add image", action: onAddImage)
        }
        .padding(.horizontal, CanvasBottomToolbarMetrics.horizontalPadding)
        .padding(.vertical, CanvasBottomToolbarMetrics.verticalPadding)
        .background {
            #if os(iOS)
            ZStack {
                RoundedRectangle(cornerRadius: CanvasBottomToolbarMetrics.barCornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                RoundedRectangle(cornerRadius: CanvasBottomToolbarMetrics.barCornerRadius, style: .continuous)
                    .fill(AppColors.floatingChrome)
            }
            #else
            RoundedRectangle(cornerRadius: CanvasBottomToolbarMetrics.barCornerRadius, style: .continuous)
                .fill(AppColors.floatingChrome)
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: CanvasBottomToolbarMetrics.barCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CanvasBottomToolbarMetrics.barCornerRadius, style: .continuous)
                .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.floatingChromeShadow, radius: 12, y: 3)
        .padding(.bottom, bottomPadding)
    }

    private func bottomButton(_ name: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: CanvasBottomToolbarMetrics.iconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(AppColors.textPrimary.opacity(0.88))
                .frame(
                    width: CanvasBottomToolbarMetrics.buttonWidth,
                    height: CanvasBottomToolbarMetrics.buttonHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(CanvasIPadBottomToolbarButtonStyle())
        .accessibilityLabel(tip)
    }
}

private struct CanvasIPadBottomToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: CanvasBottomToolbarMetrics.buttonCornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? AppColors.toolbarButtonPressed : Color.clear)
            )
    }
}
