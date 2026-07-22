#if os(iOS)
import SwiftUI

// MARK: - Slim left icon rail (iPad)

enum IPadShellMetrics {
    /// ~30% larger than the first Obsidian-sized draft for comfortable iPad touch.
    static let railWidth: CGFloat = 72
    static let sidebarWidth: CGFloat = 390
    static let panelCornerRadius: CGFloat = 28
    static let railCornerRadius: CGFloat = 22
    static let touchTarget: CGFloat = 52
    static let iconSize: CGFloat = 20
    static let headerFontSize: CGFloat = 17
    static let footerTitleSize: CGFloat = 17
    static let footerMetaSize: CGFloat = 13
    static let panelPadding: CGFloat = 16
}

private struct IPadRailButton: View {
    let systemName: String
    let label: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: IPadShellMetrics.iconSize, weight: .regular))
                .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(width: IPadShellMetrics.touchTarget, height: IPadShellMetrics.touchTarget)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? AppColors.sidebarSelection : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct IPadIconRail: View {
    @Binding var sidebarVisible: Bool
    @Binding var sidebarPanel: SidebarPanel
    var isGraphActive = false
    var isCanvasActive = false
    var onGoToFile: () -> Void = {}
    var onOpenGraph: () -> Void = {}
    var onCreateCanvas: () -> Void = {}
    var onCreateNote: () -> Void = {}
    var onManageVaults: () -> Void = {}
    var onSwipeToDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            IPadRailButton(systemName: "magnifyingglass", label: "Go to file") {
                onGoToFile()
            }
            IPadRailButton(
                systemName: "point.3.connected.trianglepath.dotted",
                label: "Open graph view",
                isActive: isGraphActive
            ) {
                onOpenGraph()
            }
            IPadRailButton(
                systemName: "square.grid.2x2",
                label: "Create new canvas",
                isActive: isCanvasActive
            ) {
                onCreateCanvas()
            }
            IPadRailButton(systemName: "doc.badge.plus", label: "New note") {
                onCreateNote()
            }
            IPadRailButton(systemName: "square.stack.3d.up", label: "Manage vaults") {
                onManageVaults()
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(width: IPadShellMetrics.railWidth)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: IPadShellMetrics.railCornerRadius, style: .continuous)
                .fill(AppColors.overlayPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IPadShellMetrics.railCornerRadius, style: .continuous)
                .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.floatingChromeShadow, radius: 24, y: 8)
        .modifier(
            IPadSidebarSwipeDismissModifier(
                enabled: onSwipeToDismiss != nil,
                onDismiss: { onSwipeToDismiss?() }
            )
        )
    }
}

// MARK: - Floating overlay sidebar (iPad)

private struct IPadSidebarSwipeDismissModifier: ViewModifier {
    var enabled: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.width < -40,
                           abs(value.translation.width) > abs(value.translation.height) * 1.2 {
                            onDismiss()
                        }
                    }
            )
        } else {
            content
        }
    }
}

struct IPadFloatingSidebar: View {
    @Bindable var workspace: WorkspaceStore
    @Binding var sidebarVisible: Bool
    @Binding var sidebarPanel: SidebarPanel
    @Binding var isPinned: Bool
    var panelWidth: CGFloat = IPadShellMetrics.sidebarWidth
    var onOpenDocument: ((WorkspaceFileEntry) -> Void)? = nil
    var onSwipeToDismiss: (() -> Void)?

    private var fileFolderSummary: String {
        let folders = workspace.files.filter { $0.kind == .folder }.count
        let files = workspace.files.count - folders
        return "\(files) file\(files == 1 ? "" : "s"), \(folders) folder\(folders == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 0) {
            panelSwitcherHeader
                .padding(.horizontal, IPadShellMetrics.panelPadding)
                .padding(.top, IPadShellMetrics.panelPadding)
                .padding(.bottom, 6)

            SidebarView(
                workspace: workspace,
                sidebarVisible: $sidebarVisible,
                sidebarPanel: $sidebarPanel,
                activePanel: sidebarPanel,
                floatingStyle: true,
                onOpenDocument: onOpenDocument
            )

            footer
                .padding(.horizontal, IPadShellMetrics.panelPadding + 4)
                .padding(.vertical, IPadShellMetrics.panelPadding)
        }
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: IPadShellMetrics.panelCornerRadius, style: .continuous)
                .fill(AppColors.overlayPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IPadShellMetrics.panelCornerRadius, style: .continuous)
                .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: IPadShellMetrics.panelCornerRadius, style: .continuous))
        .shadow(color: AppColors.floatingChromeShadow, radius: 24, y: 8)
        .modifier(
            IPadSidebarSwipeDismissModifier(
                enabled: onSwipeToDismiss != nil && !isPinned,
                onDismiss: { onSwipeToDismiss?() }
            )
        )
        .onAppear {
            let normalized = SidebarPanel.normalized(sidebarPanel)
            if normalized != sidebarPanel {
                sidebarPanel = normalized
            }
        }
    }

    // MARK: Header — "Files" pill with panel dropdown

    private var panelSwitcherHeader: some View {
        Menu {
            ForEach(SidebarPanel.shippedPanels, id: \.self) { panel in
                Button {
                    sidebarPanel = panel
                } label: {
                    if panel == sidebarPanel {
                        Label(panel.displayName, systemImage: "checkmark")
                    } else {
                        Label(panel.displayName, systemImage: panel.iconName)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: sidebarPanel.iconName)
                    .font(.system(size: IPadShellMetrics.headerFontSize - 1, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                Text(sidebarPanel.displayName)
                    .font(.system(size: IPadShellMetrics.headerFontSize, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: IPadShellMetrics.touchTarget)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.sidebarSelection)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    // MARK: Footer — vault info + settings / help

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            Menu {
                ForEach(workspace.vaults) { vault in
                    Button {
                        workspace.switchVault(vault.id)
                    } label: {
                        if vault.id == workspace.activeVault?.id {
                            Label(vault.name, systemImage: "checkmark")
                        } else {
                            Text(vault.name)
                        }
                    }
                }
                Divider()
                Button("Manage vaults...") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        workspace.isVaultManagerOpen = true
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(workspace.vaultName)
                            .font(.system(size: IPadShellMetrics.footerTitleSize, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColors.textMuted)
                    }
                    Text(fileFolderSummary)
                        .font(.system(size: IPadShellMetrics.footerMetaSize))
                        .foregroundStyle(AppColors.textMuted)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 0)

            footerCircleButton(systemName: "gearshape", label: "Settings") {
                withAnimation(.easeOut(duration: 0.15)) {
                    workspace.isVaultManagerOpen = true
                }
            }
            footerCircleButton(systemName: "questionmark.circle", label: "Help") {
                withAnimation(.easeOut(duration: 0.15)) {
                    workspace.isHelpOpen = true
                }
            }
        }
    }

    private func footerCircleButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: IPadShellMetrics.iconSize - 2, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: IPadShellMetrics.touchTarget, height: IPadShellMetrics.touchTarget)
                .background(Circle().fill(AppColors.sidebarSelection))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
#endif
