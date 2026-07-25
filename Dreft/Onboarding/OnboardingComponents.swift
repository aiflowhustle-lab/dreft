import SwiftUI

// MARK: - Layout

enum OnboardingLayout {
    static let contentMaxWidth: CGFloat = 520
    static let macWindowSize = CGSize(width: 720, height: 560)
    static let pinnedFooterHeight: CGFloat = 52
    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 28

    #if os(iOS)
    static let iPadPinnedFooterHeight: CGFloat = 56
    static let iPadHorizontalPaddingRegular: CGFloat = 40
    static let iPadHorizontalPaddingCompact: CGFloat = 24
    static let iPadContentMaxWidthRegular: CGFloat = 560
    static let iPadTopInset: CGFloat = 8
    static let iPadContentFooterSpacing: CGFloat = 28
    static let iPadBottomInset: CGFloat = 32
    #endif

    #if os(iOS)
    static func iPadContentMaxWidth(isRegular: Bool) -> CGFloat {
        isRegular ? iPadContentMaxWidthRegular : 520
    }

    static func iPadHorizontalPadding(isRegular: Bool) -> CGFloat {
        isRegular ? iPadHorizontalPaddingRegular : iPadHorizontalPaddingCompact
    }
    #endif
}

struct OnboardingScreenChrome<Content: View, Footer: View>: View {
    let showsBack: Bool
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iPadBody
        #endif
    }

    // MARK: Mac — fixed centered panel

    private var macBody: some View {
        ZStack {
            OnboardingAmbientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                backButtonRow

                Spacer(minLength: 12)

                content()
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 12)

                footer()
                    .frame(height: OnboardingLayout.pinnedFooterHeight, alignment: .center)
            }
            .frame(maxWidth: OnboardingLayout.contentMaxWidth)
            .padding(.horizontal, OnboardingLayout.horizontalPadding)
            .padding(.vertical, OnboardingLayout.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(width: OnboardingLayout.macWindowSize.width, height: OnboardingLayout.macWindowSize.height)
    }

    // MARK: iPad — fullscreen, vertically centered, pinned footer above home indicator

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var keyboard = KeyboardHeightObserver()

    private var iPadBody: some View {
        GeometryReader { geo in
            let isRegular = horizontalSizeClass == .regular
            let maxWidth = OnboardingLayout.iPadContentMaxWidth(isRegular: isRegular)
            let sidePadding = OnboardingLayout.iPadHorizontalPadding(isRegular: isRegular)
            let topBarHeight: CGFloat = showsBack ? 44 : OnboardingLayout.iPadTopInset
            let scrollMinHeight = max(
                0,
                geo.size.height
                    - topBarHeight
                    - geo.safeAreaInsets.top
                    - geo.safeAreaInsets.bottom
                    - OnboardingLayout.iPadBottomInset
            )

            ZStack {
                OnboardingAmbientBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    backButtonRow
                        .padding(.top, geo.safeAreaInsets.top + OnboardingLayout.iPadTopInset)
                        .padding(.horizontal, sidePadding)

                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: OnboardingLayout.iPadContentFooterSpacing) {
                                content()
                                footer()
                                    .id(OnboardingScrollAnchor.footer)
                            }
                            .frame(maxWidth: maxWidth)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, sidePadding)
                            .padding(.bottom, keyboard.isVisible ? keyboard.height + 16 : 0)
                            .frame(
                                minHeight: keyboard.isVisible ? 0 : scrollMinHeight,
                                alignment: keyboard.isVisible ? .top : .center
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: keyboard.isVisible) { _, visible in
                            guard visible else { return }
                            scrollFooterIntoView(proxy)
                        }
                        .onChange(of: keyboard.height) { _, height in
                            guard height > 0 else { return }
                            scrollFooterIntoView(proxy)
                        }
                    }
                }
                .padding(.bottom, keyboard.isVisible ? 0 : max(geo.safeAreaInsets.bottom, OnboardingLayout.iPadBottomInset))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollFooterIntoView(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(OnboardingScrollAnchor.footer, anchor: .bottom)
            }
        }
    }
    #endif

    @ViewBuilder
    private var backButtonRow: some View {
        if showsBack {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.vertical, 8)
                    .padding(.trailing, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .keyboardShortcut(.cancelAction)
                #endif
                Spacer()
            }
            .padding(.bottom, 4)
        } else {
            Color.clear.frame(height: 4)
        }
    }
}

private enum OnboardingScrollAnchor {
    static let footer = "onboarding.footer"
}

extension OnboardingScreenChrome where Footer == EmptyView {
    init(
        showsBack: Bool,
        onBack: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(showsBack: showsBack, onBack: onBack, content: content, footer: { EmptyView() })
    }
}

/// Wraps onboarding for full-screen presentation on iPad and Mac.
struct OnboardingPresentationContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            AppColors.canvasBackground.ignoresSafeArea()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Buttons

struct OnboardingPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingColors.buttonText(for: colorScheme).opacity(enabled ? 1 : 0.5))
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
                .frame(minHeight: minTouchHeight)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(OnboardingColors.buttonFill(for: colorScheme).opacity(enabled ? 1 : 0.35))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        #if os(macOS)
        .keyboardShortcut(.defaultAction)
        #endif
    }

    private var minTouchHeight: CGFloat {
        #if os(iOS)
        AppColors.minimumTouchTarget
        #else
        0
        #endif
    }
}

struct OnboardingPrimaryFooter: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            OnboardingPrimaryButton(title: title, enabled: enabled, action: action)
            Spacer(minLength: 0)
        }
    }
}

struct OnboardingSplitFooter: View {
    let leadingTitle: String
    let leadingAction: () -> Void
    let trailingTitle: String
    var trailingEnabled: Bool = true
    let trailingAction: () -> Void

    var body: some View {
        #if os(iOS)
        VStack(spacing: 14) {
            Button(leadingTitle, action: leadingAction)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .buttonStyle(.plain)
                .frame(minHeight: AppColors.minimumTouchTarget)

            OnboardingPrimaryButton(
                title: trailingTitle,
                enabled: trailingEnabled,
                action: trailingAction
            )
        }
        .frame(maxWidth: .infinity)
        #else
        HStack {
            Button(leadingTitle, action: leadingAction)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .buttonStyle(.plain)

            Spacer()

            OnboardingPrimaryButton(
                title: trailingTitle,
                enabled: trailingEnabled,
                action: trailingAction
            )
        }
        #endif
    }
}

// MARK: - Ambient background

struct OnboardingAmbientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppColors.canvasBackground

            if reduceMotion {
                OnboardingAmbientCardsLayer(phase: 0, colorScheme: colorScheme)
                    .opacity(0.12)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (t.truncatingRemainder(dividingBy: 20)) / 20
                    OnboardingAmbientCardsLayer(phase: phase, colorScheme: colorScheme)
                        .opacity(0.15)
                }
            }

            LinearGradient(
                colors: [
                    AppColors.canvasBackground.opacity(0.35),
                    AppColors.canvasBackground.opacity(0.72),
                    AppColors.canvasBackground.opacity(0.92),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct OnboardingAmbientCardsLayer: View {
    let phase: Double
    var colorScheme: ColorScheme = .light

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lineColor = OnboardingColors.accent(for: colorScheme).opacity(0.18)

            ZStack {
                ambientCard(width: w * 0.22, height: h * 0.14, x: w * 0.18 + drift(12, offset: 0), y: h * 0.22 + drift(8, offset: 0.2))
                ambientCard(width: w * 0.18, height: h * 0.11, x: w * 0.72 + drift(10, offset: 0.45), y: h * 0.18 + drift(6, offset: 0.6))
                ambientCard(width: w * 0.2, height: h * 0.12, x: w * 0.62 + drift(14, offset: 0.75), y: h * 0.58 + drift(9, offset: 0.3))
                ambientCard(width: w * 0.16, height: h * 0.1, x: w * 0.28 + drift(8, offset: 0.9), y: h * 0.62 + drift(11, offset: 0.15))
                ambientCard(width: w * 0.14, height: h * 0.09, x: w * 0.48 + drift(6, offset: 0.55), y: h * 0.42 + drift(7, offset: 0.85))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.28, y: h * 0.28))
                    path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.36))
                    path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.52))
                }
                .stroke(lineColor, lineWidth: 1)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.34, y: h * 0.66))
                    path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.48))
                }
                .stroke(lineColor.opacity(0.75), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func drift(_ amplitude: CGFloat, offset: Double) -> CGFloat {
        CGFloat(sin((phase + offset) * .pi * 2)) * amplitude
    }

    private func ambientCard(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(AppColors.cardBackground.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(OnboardingColors.accentMuted(for: colorScheme), lineWidth: 1)
            )
            .frame(width: width, height: height)
            .position(x: x, y: y)
    }
}

// MARK: - Building transition

struct OnboardingBuildingView: View {
    let worldName: String?
    let onFinished: () -> Void

    @State private var visibleChecks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private let checks = [
        ("rectangle.on.rectangle.angled", OnboardingCopy.buildingCheckCanvas),
        ("doc.text", OnboardingCopy.buildingCheckLore),
        ("point.3.connected.trianglepath.dotted", OnboardingCopy.buildingCheckGraph),
    ]

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
                .tint(OnboardingColors.accent(for: colorScheme))

            Text(OnboardingCopy.buildingTitle(worldName: worldName))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                    HStack(spacing: 10) {
                        Image(systemName: index < visibleChecks ? "checkmark.circle.fill" : check.0)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(
                                index < visibleChecks
                                    ? OnboardingColors.accent(for: colorScheme)
                                    : AppColors.textMuted
                            )
                        Text(check.1)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                index < visibleChecks ? AppColors.textPrimary : AppColors.textMuted
                            )
                    }
                    .opacity(index <= visibleChecks ? 1 : 0.45)
                }
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .frame(maxHeight: .infinity)
        #endif
        .task {
            let stepDelay: UInt64 = reduceMotion ? 150_000_000 : OnboardingMotion.buildingStepDelay
            for index in 1...checks.count {
                try? await Task.sleep(nanoseconds: stepDelay)
                if reduceMotion {
                    visibleChecks = index
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        visibleChecks = index
                    }
                }
            }
            try? await Task.sleep(nanoseconds: reduceMotion ? 150_000_000 : 350_000_000)
            onFinished()
        }
    }
}

// MARK: - Vault error alert

extension View {
    func vaultErrorAlert(workspace: WorkspaceStore) -> some View {
        alert(
            workspace.vaultAlert?.title ?? "Vault error",
            isPresented: Binding(
                get: { workspace.vaultAlert != nil },
                set: { isPresented in
                    if !isPresented {
                        workspace.clearVaultAlert()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                workspace.clearVaultAlert()
            }
        } message: {
            Text(workspace.vaultAlert?.message ?? "")
        }
    }
}
