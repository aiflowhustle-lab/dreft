import SwiftUI

struct ShellRailTooltip: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            ShellRailTooltipArrow()
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.11, green: 0.11, blue: 0.11))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .fixedSize()
        .allowsHitTesting(false)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }
}

private struct ShellRailTooltipArrow: View {
    var body: some View {
        ShellRailTooltipArrowShape()
            .fill(Color(red: 0.11, green: 0.11, blue: 0.11))
            .frame(width: 6, height: 12)
            .overlay {
                ShellRailTooltipArrowShape()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct ShellRailTooltipArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct IconRailButton: View {
    let systemName: String?
    let textLabel: String?
    let tooltip: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(
        systemName: String,
        tooltip: String,
        isActive: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.systemName = systemName
        self.textLabel = nil
        self.tooltip = tooltip
        self.isActive = isActive
        self.action = action
    }

    init(
        textLabel: String,
        tooltip: String,
        isActive: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.systemName = nil
        self.textLabel = textLabel
        self.tooltip = tooltip
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 16, weight: .regular))
                } else if let textLabel {
                    Text(textLabel)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                }
            }
            .foregroundStyle(isActive || isHovered ? AppColors.textPrimary : AppColors.textSecondary)
            .frame(width: 28, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive || isHovered ? AppColors.sidebarSelection : Color.clear)
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            DispatchQueue.main.async {
                isHovered = hovering
            }
        }
        #endif
        .overlay(alignment: .leading) {
            if isHovered {
                ShellRailTooltip(text: tooltip)
                    .offset(x: 32)
                    .zIndex(200)
            }
        }
        .help(tooltip)
    }
}

struct IconRailView: View {
    @Bindable var workspace: WorkspaceStore
    @Binding var sidebarVisible: Bool
    var onGoToFile: () -> Void = {}
    var contentTopInset: CGFloat = AppColors.macTrafficLightInset

    private var isGraphActive: Bool {
        workspace.activeTab?.kind == .graph
    }

    private var isCanvasActive: Bool {
        workspace.activeTab?.kind == .canvas
    }

    private var railSurfaceColor: Color {
        #if os(macOS)
        sidebarVisible ? AppColors.railBackground : AppColors.canvasBackground
        #else
        AppColors.railBackground
        #endif
    }

    private var railHeaderColor: Color {
        #if os(macOS)
        sidebarVisible ? AppColors.tabBarBackground : AppColors.canvasBackground
        #else
        AppColors.tabBarBackground
        #endif
    }

    #if os(macOS)
    private var iconStackTopPadding: CGFloat {
        if !sidebarVisible {
            AppColors.chromeRowHeight
        } else {
            max(0, contentTopInset - AppColors.chromeRowHeight)
        }
    }
    #else
    private var iconStackTopPadding: CGFloat {
        max(0, contentTopInset - AppColors.chromeRowHeight)
    }
    #endif

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            if sidebarVisible {
                railHeaderColor
                    .frame(height: AppColors.chromeRowHeight)
            }
            #else
            railHeaderColor
                .frame(height: AppColors.chromeRowHeight)
            #endif

            VStack(spacing: 4) {
                IconRailButton(systemName: "magnifyingglass", tooltip: "Go to file") {
                    onGoToFile()
                }
                IconRailButton(
                    systemName: "point.3.connected.trianglepath.dotted",
                    tooltip: "Open graph view",
                    isActive: isGraphActive
                ) {
                    workspace.openGraphTab()
                }
                IconRailButton(
                    systemName: "square.grid.2x2",
                    tooltip: "Create new canvas",
                    isActive: isCanvasActive
                ) {
                    workspace.createCanvas()
                }
                IconRailButton(systemName: "doc.badge.plus", tooltip: "New note") {
                    workspace.createNote()
                }
                IconRailButton(systemName: "square.stack.3d.up", tooltip: "Manage vaults") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        workspace.isVaultManagerOpen = true
                    }
                }
            }
            .padding(.top, iconStackTopPadding)

            Spacer(minLength: 0)
        }
        .frame(width: 40)
        .frame(maxHeight: .infinity)
        .background(railSurfaceColor)
        #if os(macOS)
        .zIndex(sidebarVisible ? 2 : 0)
        #else
        .zIndex(2)
        #endif
    }
}
