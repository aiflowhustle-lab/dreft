import SwiftUI

/// Obsidian-style bottom creation toolbar for iPad canvas — a compact
/// rounded bar with three document icons, matching the canvas references.
struct CanvasIPadBottomToolbar: View {
    var onAddCard: () -> Void
    var onVaultNote: () -> Void
    var onAddImage: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            bottomButton("doc", tip: "Add card", action: onAddCard)
            bottomButton("doc.text", tip: "Vault note", action: onVaultNote)
            bottomButton("doc.circle", tip: "Add image", action: onAddImage)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.floatingChrome)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.floatingChromeShadow, radius: 12, y: 3)
        .padding(.bottom, 18)
    }

    private func bottomButton(_ name: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 15, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(AppColors.textPrimary.opacity(0.88))
                .frame(width: 36, height: 34)
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? AppColors.toolbarButtonPressed : Color.clear)
            )
    }
}
