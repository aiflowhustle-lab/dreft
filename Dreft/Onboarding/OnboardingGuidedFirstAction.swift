import SwiftUI

/// One-time spotlight after onboarding, routed by `CoreDesire`.
struct OnboardingGuidedFirstActionOverlay: View {
    let desire: CoreDesire
    let vaultPath: String?
    let timelapseAnchor: CGRect?
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: tooltipAlignment) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            if let timelapseAnchor, desire == .finish {
                spotlightCutout(around: timelapseAnchor)
            }

            tooltipCard
                .padding(24)
        }
        .transition(.opacity)
    }

    private var tooltipAlignment: Alignment {
        switch desire {
        case .finish:
            return .bottomLeading
        case .canon, .map, .own:
            return .bottom
        }
    }

    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(OnboardingCopy.guidedMessage(for: desire))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if desire == .own, let vaultPath {
                Text(vaultPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack {
                Spacer()
                Button("Got it", action: onDismiss)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingColors.accent(for: colorScheme))
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.overlayPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
                )
        )
        .shadow(color: AppColors.floatingChromeShadow, radius: 20, y: 8)
    }

    @ViewBuilder
    private func spotlightCutout(around rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(OnboardingColors.accent(for: colorScheme), lineWidth: 2)
            .frame(width: rect.width + 8, height: rect.height + 8)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

struct OnboardingGuidedFirstActionModifier: ViewModifier {
    @Bindable var workspace: WorkspaceStore
    @State private var isVisible = false
    @State private var desire: CoreDesire?

    func body(content: Content) -> some View {
        content
            .overlay {
                if isVisible, let desire {
                    OnboardingGuidedFirstActionOverlay(
                        desire: desire,
                        vaultPath: workspace.activeVault?.path,
                        timelapseAnchor: nil,
                        onDismiss: dismiss
                    )
                }
            }
            .onAppear(perform: tryPresent)
            .onChange(of: workspace.activeTab?.kind) { _, _ in
                tryPresent()
            }
    }

    private func tryPresent() {
        guard OnboardingPersistence.shouldShowGuidedAction(),
              workspace.activeTab?.kind == .canvas,
              let pending = OnboardingPersistence.pendingCoreDesire() else {
            return
        }
        desire = pending
        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = true
        }
    }

    private func dismiss() {
        OnboardingPersistence.markGuidedActionShown()
        OnboardingPersistence.setPendingCoreDesire(nil)
        withAnimation(.easeOut(duration: 0.15)) {
            isVisible = false
        }
    }
}

extension View {
    func onboardingGuidedFirstAction(workspace: WorkspaceStore) -> some View {
        modifier(OnboardingGuidedFirstActionModifier(workspace: workspace))
    }
}
