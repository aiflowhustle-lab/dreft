import SwiftUI

// MARK: - Backdrop

struct SeamlessOnboardingBackdrop: View {
    let step: OnboardingStep
    let usesBrightLandscape: Bool

    @State private var drift = false

    var body: some View {
        ZStack {
            AppColors.canvasBackground

            Image("onboarding-ambient-night")
                .resizable()
                .scaledToFill()
                .opacity(showsNightWash ? 0.05 : 0)
                .scaleEffect(drift ? 1.12 : 1.06)
                .offset(x: drift ? -8 : 0, y: drift ? -6 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 34).repeatForever(autoreverses: true), value: drift)

            Image("onboarding-ambient-vale")
                .resizable()
                .scaledToFill()
                .opacity(showsValeWash ? (usesBrightLandscape ? 0.1 : 0.05) : 0)
                .scaleEffect(drift ? 1.12 : 1.06)
                .offset(x: drift ? -8 : 0, y: drift ? -6 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 34).repeatForever(autoreverses: true), value: drift)

            DotGridBackground(
                panOffset: .zero,
                dotColor: AppColors.gridDotColor.opacity(0.7)
            )
            .opacity(0.55)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.6), value: showsValeWash)
        .animation(.easeInOut(duration: 1.6), value: usesBrightLandscape)
        .onAppear {
            guard !reduceMotion else { return }
            drift = true
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsNightWash: Bool {
        step == .displayName || step == .goals
    }

    private var showsValeWash: Bool {
        step != .displayName && step != .goals
    }
}

// MARK: - Progress

struct SeamlessOnboardingProgress: View {
    let current: OnboardingStep

    private let trackedSteps: [OnboardingStep] = [
        .displayName, .goals, .revealHome, .genre, .worldName,
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(trackedSteps.enumerated()), id: \.offset) { index, step in
                Capsule()
                    .fill(
                        index == currentIndex
                            ? AppColors.textPrimary.opacity(0.8)
                            : AppColors.textPrimary.opacity(0.25)
                    )
                    .frame(width: index == currentIndex ? 24 : 6, height: 4)
                    .animation(.easeInOut(duration: 0.5), value: currentIndex)
            }
        }
        .padding(.bottom, 28)
        .allowsHitTesting(false)
    }

    private var currentIndex: Int {
        trackedSteps.firstIndex(of: current) ?? 0
    }
}

// MARK: - Typewriter

struct OnboardingTypewriterText: View {
    let text: String
    var font: Font
    var color: Color = AppColors.textPrimary
    var alignment: TextAlignment = .leading
    var italic: Bool = false
    var showsCursor: Bool = true
    var characterDelayMs: Int = OnboardingMotion.typewriterCharacterDelayMs
    var startDelayMs: Int = 0
    var onComplete: (() -> Void)?

    @State private var visibleCount = 0
    @State private var cursorVisible = true
    @State private var isTyping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(displayText)
            .font(font)
            .italic(italic)
            .foregroundStyle(color)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .task(id: text) {
                await runAnimation()
            }
            .task(id: isTyping) {
                guard isTyping, showsCursor, !reduceMotion else { return }
                while !Task.isCancelled, isTyping {
                    try? await Task.sleep(for: .milliseconds(530))
                    cursorVisible.toggle()
                }
            }
    }

    private var displayText: String {
        let typed = String(text.prefix(visibleCount))
        guard showsCursor, isTyping, cursorVisible else { return typed }
        return typed + "|"
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }

    @MainActor
    private func runAnimation() async {
        visibleCount = 0
        cursorVisible = true

        if reduceMotion {
            visibleCount = text.count
            isTyping = false
            onComplete?()
            return
        }

        isTyping = true
        if startDelayMs > 0 {
            try? await Task.sleep(for: .milliseconds(startDelayMs))
        }

        for index in 1...text.count {
            try? await Task.sleep(for: .milliseconds(characterDelayMs))
            guard !Task.isCancelled else { return }
            visibleCount = index
        }

        isTyping = false
        onComplete?()
    }
}

// MARK: - Shell

struct SeamlessStepShell<Content: View>: View {
    let title: String
    var subtitle: String?
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder let content: () -> Content

    @State private var showSubtitle = false
    @State private var showContent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            OnboardingTypewriterText(
                text: title,
                font: OnboardingTypography.display(size: titleSize, weight: .bold),
                alignment: textAlignment,
                onComplete: {
                    showSubtitle = true
                    if subtitle == nil {
                        showContent = true
                    }
                }
            )

            if let subtitle, showSubtitle || reduceMotion {
                OnboardingTypewriterText(
                    text: subtitle,
                    font: OnboardingTypography.body(size: subtitleSize),
                    color: AppColors.textSecondary,
                    alignment: textAlignment,
                    showsCursor: false,
                    characterDelayMs: 24,
                    startDelayMs: reduceMotion ? 0 : OnboardingMotion.typewriterSubtitleDelayMs,
                    onComplete: { showContent = true }
                )
                .padding(.top, 12)
            }

            content()
                .padding(.top, 32)
                .opacity(showContent || reduceMotion ? 1 : 0)
                .offset(y: showContent || reduceMotion ? 0 : 14)
                .animation(
                    reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.55),
                    value: showContent
                )
        }
        .frame(maxWidth: 600)
        .padding(.horizontal, 24)
        .onAppear {
            guard reduceMotion else { return }
            showSubtitle = true
            showContent = true
        }
    }

    private var textAlignment: TextAlignment {
        alignment == .center ? .center : .leading
    }

    private var titleSize: CGFloat {
        #if os(iOS)
        28
        #else
        34
        #endif
    }

    private var subtitleSize: CGFloat {
        #if os(iOS)
        16
        #else
        17
        #endif
    }
}

// MARK: - Controls

struct SeamlessGhostField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(AppColors.textMuted.opacity(0.7)))
            .textFieldStyle(.plain)
            .font(OnboardingTypography.body(size: 17))
            .italic()
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColors.canvasBackground.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isFocused ? AppColors.textPrimary.opacity(0.35) : AppColors.border,
                                lineWidth: 1
                            )
                    )
            )
            .focused($isFocused)
            .onSubmit { onSubmit?() }
            .accessibilityLabel(label)
            .onAppear { isFocused = true }
    }
}

struct SeamlessPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var fullWidth: Bool = true
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OnboardingTypography.body(size: 15, weight: .medium))
                .foregroundStyle(enabled ? OnboardingColors.buttonText(for: colorScheme) : AppColors.textMuted)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, fullWidth ? 0 : 28)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(enabled ? OnboardingColors.buttonFill(for: colorScheme) : AppColors.borderSubtle)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct SeamlessGhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
                .frame(height: 48)
                .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
    }
}

struct SeamlessSkipButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .underline(true, color: AppColors.textSecondary.opacity(0.001))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

struct SeamlessOptionCard: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.85))
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppColors.textPrimary.opacity(0.55) : AppColors.border, lineWidth: 1)
            )
            .shadow(color: isSelected ? AppColors.floatingChromeShadow : .clear, radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var glassBackground: some View {
        #if os(iOS)
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.thinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? AppColors.textPrimary.opacity(0.08) : AppColors.floatingChrome.opacity(0.72))
        }
        #else
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isSelected ? AppColors.textPrimary.opacity(0.08) : AppColors.floatingChrome)
        #endif
    }
}

struct SeamlessGenreChip: View {
    let title: String
    var symbolName: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 14, weight: .medium))
                        .opacity(0.85)
                }
                Text(title)
                    .font(.system(size: 14))
                    .lineLimit(1)
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(glassBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? AppColors.textPrimary.opacity(0.6) : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var glassBackground: some View {
        #if os(iOS)
        ZStack {
            Capsule().fill(.thinMaterial)
            Capsule().fill(isSelected ? AppColors.textPrimary.opacity(0.08) : AppColors.floatingChrome.opacity(0.72))
        }
        #else
        Capsule().fill(isSelected ? AppColors.textPrimary.opacity(0.08) : AppColors.floatingChrome)
        #endif
    }
}

struct SeamlessWorldNameField: View {
    @Binding var text: String
    var onSubmit: (() -> Void)?
    var onPromptComplete: (() -> Void)?

    @FocusState private var isFocused: Bool
    @State private var showTypewriterPlaceholder = true
    @State private var hasFinishedPrompt = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if showsTypewriterPlaceholder {
                OnboardingTypewriterText(
                    text: OnboardingCopy.worldNamePlaceholder,
                    font: OnboardingTypography.display(size: fieldSize, weight: .medium),
                    color: placeholderColor,
                    alignment: .center,
                    showsCursor: false,
                    characterDelayMs: 28,
                    onComplete: finishPromptAnimation
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else if showsStaticPlaceholder {
                Text(OnboardingCopy.worldNamePlaceholder)
                    .font(OnboardingTypography.display(size: fieldSize, weight: .medium))
                    .foregroundStyle(placeholderColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(OnboardingTypography.display(size: fieldSize, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(text.isEmpty && (showsTypewriterPlaceholder || showsStaticPlaceholder) ? .clear : AppColors.textPrimary)
                .focused($isFocused)
                .onSubmit { onSubmit?() }
                .accessibilityLabel(OnboardingCopy.worldNamePlaceholder)
                .allowsHitTesting(!showsTypewriterPlaceholder)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard showsTypewriterPlaceholder else { return }
            skipToEditing()
        }
        .onAppear {
            showTypewriterPlaceholder = !reduceMotion
            if reduceMotion {
                hasFinishedPrompt = true
                onPromptComplete?()
            }
        }
        .onChange(of: text) { _, newValue in
            if !newValue.isEmpty {
                skipToEditing()
            }
        }
    }

    private var showsTypewriterPlaceholder: Bool {
        text.isEmpty && showTypewriterPlaceholder && !reduceMotion
    }

    private var showsStaticPlaceholder: Bool {
        text.isEmpty && hasFinishedPrompt && !showsTypewriterPlaceholder
    }

    private var placeholderColor: Color {
        AppColors.textMuted.opacity(0.35)
    }

    private func finishPromptAnimation() {
        guard !hasFinishedPrompt else { return }
        hasFinishedPrompt = true
        showTypewriterPlaceholder = false
        onPromptComplete?()
        isFocused = true
    }

    private func skipToEditing() {
        showTypewriterPlaceholder = false
        guard !hasFinishedPrompt else {
            isFocused = true
            return
        }
        hasFinishedPrompt = true
        onPromptComplete?()
        isFocused = true
    }

    private var fieldSize: CGFloat {
        #if os(iOS)
        28
        #else
        42
        #endif
    }
}

// MARK: - Interstitial

struct SeamlessInterstitial: View {
    let line: String
    var italic: Bool = false
    var showsSpinner: Bool = false
    let onDone: () -> Void

    @State private var typingComplete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onDone) {
            VStack(spacing: 40) {
                if showsSpinner {
                    SeamlessSpinner()
                }

                OnboardingTypewriterText(
                    text: line,
                    font: OnboardingTypography.display(size: interstitialSize, weight: .medium),
                    alignment: .center,
                    italic: italic,
                    onComplete: {
                        typingComplete = true
                        scheduleAutoAdvance()
                    }
                )
                .frame(maxWidth: 900)

                Text(OnboardingCopy.interstitialSkipHint)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textMuted.opacity(0.7))
                    .opacity(typingComplete || reduceMotion ? 1 : 0)
                    .animation(.easeOut(duration: 0.35), value: typingComplete)
            }
            .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
        .onDisappear {
            typingComplete = false
        }
    }

    private func scheduleAutoAdvance() {
        let delay = reduceMotion ? 0.05 : 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard typingComplete else { return }
            onDone()
        }
    }

    private var interstitialSize: CGFloat {
        #if os(iOS)
        28
        #else
        42
        #endif
    }
}

struct SeamlessSpinner: View {
    @State private var rotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.92)
            .stroke(
                AppColors.textPrimary.opacity(0.18),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .overlay {
                Circle()
                    .trim(from: 0.08, to: 0.35)
                    .stroke(AppColors.textPrimary.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 32, height: 32)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
