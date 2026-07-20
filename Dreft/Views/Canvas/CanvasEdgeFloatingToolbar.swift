import SwiftUI

/// Floating toolbar for a selected connection line — matches Obsidian canvas line chrome.
struct CanvasEdgeFloatingToolbar: View {
    let direction: CanvasEdgeDirection
    var hasActiveColor: Bool = false
    @Binding var showColorRow: Bool
    var onDelete: () -> Void
    var onZoomToLine: () -> Void
    var onSetDirection: (CanvasEdgeDirection) -> Void
    var onEditLabel: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            ToolbarIconButton(systemName: "trash", tip: "Delete line", action: onDelete)
            ToolbarIconButton(
                systemName: "paintpalette",
                tip: "Set color",
                isActive: showColorRow || hasActiveColor
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    showColorRow.toggle()
                }
            }
            ToolbarIconButton(systemName: "viewfinder", tip: "Zoom to line", action: onZoomToLine)

            directionMenu

            ToolbarIconButton(systemName: "square.and.pencil", tip: "Edit line label", action: onEditLabel)
        }
        .padding(3)
        .background(AppColors.canvasBackground.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.floatingChromeShadow, radius: 10, y: 3)
        .fixedSize()
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var directionMenu: some View {
        Menu {
            ForEach(CanvasEdgeDirection.allCases) { option in
                Button {
                    onSetDirection(option)
                } label: {
                    if option == direction {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Label(option.title, systemImage: option.iconName)
                    }
                }
            }
        } label: {
            Image(systemName: direction.iconName)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 30, height: 26)
                .foregroundStyle(AppColors.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppColors.sidebarSelection)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Line direction")
    }

    private struct ToolbarIconButton: View {
        let systemName: String
        let tip: String
        var isActive: Bool = false
        let action: () -> Void
        @State private var hovered = false

        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 30, height: 26)
                    .foregroundStyle(
                        isActive
                            ? AppColors.selectionStroke
                            : (hovered ? AppColors.textPrimary : AppColors.textSecondary)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                isActive
                                    ? AppColors.selectionStroke.opacity(0.16)
                                    : (hovered ? AppColors.sidebarSelection : .clear)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            #if os(iOS)
            .canvasPencilToolbarHitTarget()
            #endif
            #if os(macOS)
            .onHover { hovered = $0 }
            #endif
            .help(tip)
        }
    }
}
