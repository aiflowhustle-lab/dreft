import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Seamless onboarding (name → goals → mirror → reveal → genre → world → building → ready) then app.
struct OnboardingFlowView: View {
    let isPreview: Bool
    let onComplete: () -> Void

    @StateObject private var coordinator: OnboardingCoordinator
    @State private var workspace = WorkspaceStore()
    #if os(iOS)
    @State private var folderPickerPurpose: VaultFolderPickerPurpose?
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleGenreChipCount = 0
    @State private var genreControlsVisible = false

    private var genreChipCount: Int {
        OnboardingConfig.genres.count + 1
    }
    @State private var worldNameControlsVisible = false

    init(isPreview: Bool = false, onComplete: @escaping () -> Void) {
        self.isPreview = isPreview
        self.onComplete = onComplete
        _coordinator = StateObject(wrappedValue: OnboardingCoordinator(isPreview: isPreview))
    }

    var body: some View {
        ZStack {
            SeamlessOnboardingBackdrop(
                step: coordinator.step,
                usesBrightLandscape: coordinator.usesBrightLandscape
            )

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Group {
                    switch coordinator.step {
                    case .displayName:
                        displayNameScreen
                    case .goals:
                        goalsScreen
                    case .mirror:
                        mirrorScreen
                    case .revealHome:
                        revealHomeScreen
                    case .genre:
                        genreScreen
                    case .worldName:
                        worldNameScreen
                    case .building:
                        buildingScreen
                    case .worldReady:
                        worldReadyScreen
                    }
                }
                .id(coordinator.step)
                .transition(stepTransition)

                Spacer(minLength: 0)

                if coordinator.step != .worldReady && coordinator.step != .building {
                    SeamlessOnboardingProgress(current: coordinator.step)
                }
            }
        }
        .animation(reduceMotion ? nil : OnboardingMotion.screenSlide, value: coordinator.step)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.canvasBackground)
        .onAppear { OnboardingTypography.registerFontsIfNeeded() }
        .vaultErrorAlert(workspace: workspace)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .vaultFolderPicker(purpose: $folderPickerPurpose) { url, purpose in
            handleFolderImport(url, for: purpose)
        }
        #endif
    }

    private var stepTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.985))
    }

    // MARK: - Step 1: Display name

    private var displayNameScreen: some View {
        SeamlessStepShell(
            title: OnboardingCopy.displayNameTitle,
            subtitle: OnboardingCopy.displayNameSubtitle
        ) {
            VStack(spacing: 12) {
                SeamlessGhostField(
                    label: OnboardingCopy.displayNameFieldLabel,
                    text: $coordinator.displayNameDraft,
                    placeholder: OnboardingCopy.displayNamePlaceholder,
                    onSubmit: submitDisplayName
                )

                SeamlessPrimaryButton(
                    title: OnboardingCopy.continueButton,
                    enabled: coordinator.resolvedDisplayName != nil,
                    action: submitDisplayName
                )

                SeamlessSkipButton(title: OnboardingCopy.skipButton) {
                    coordinator.skipDisplayName()
                }
            }
        }
    }

    // MARK: - Step 2: Goals

    private var goalsScreen: some View {
        SeamlessStepShell(
            title: OnboardingCopy.goalsTitle,
            subtitle: OnboardingCopy.goalsSubtitle
        ) {
            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(OnboardingConfig.goals) { goal in
                        SeamlessOptionCard(
                            title: goal.title,
                            symbolName: goal.symbolName,
                            isSelected: coordinator.state.selectedGoals.contains(goal.id),
                            action: {
                                OnboardingMotion.playSelectionHaptic()
                                coordinator.toggleGoal(goal.id)
                            }
                        )
                    }
                }

                SeamlessPrimaryButton(
                    title: OnboardingCopy.getStartedButton,
                    enabled: !coordinator.state.selectedGoals.isEmpty,
                    action: { coordinator.advanceFromGoals() }
                )
            }
        }
    }

    // MARK: - Step 3: Mirror

    private var mirrorScreen: some View {
        SeamlessMirrorScreen(
            headline: OnboardingCopy.mirrorHeadline(for: coordinator.state.selectedGoals),
            onContinue: { coordinator.advanceFromMirror() }
        )
    }

    // MARK: - Step 4: Reveal

    private var revealHomeScreen: some View {
        SeamlessInterstitial(
            line: OnboardingCopy.revealHomeLine,
            italic: true,
            onDone: { coordinator.advanceFromRevealHome() }
        )
    }

    // MARK: - Step 4: Genre

    private var genreScreen: some View {
        VStack(spacing: 0) {
            OnboardingTypewriterText(
                text: OnboardingCopy.genreTitle,
                font: OnboardingTypography.display(size: genreTitleSize, weight: .bold),
                alignment: .center,
                onComplete: startGenreChipReveal
            )
            .frame(maxWidth: 880)
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                genreRow(Array(OnboardingConfig.genres.prefix(5)), startIndex: 0)
                genreRow(Array(OnboardingConfig.genres.dropFirst(5).prefix(5)), startIndex: 5)

                HStack {
                    Spacer()
                    animatedGenreChip(index: 10, genre: OnboardingConfig.mixGenre)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)

            HStack(spacing: 8) {
                SeamlessGhostButton(title: OnboardingCopy.backButton) {
                    coordinator.goBack()
                }
                SeamlessPrimaryButton(
                    title: OnboardingCopy.continueButton,
                    enabled: coordinator.state.worldGenre != nil,
                    fullWidth: false,
                    action: { coordinator.advanceFromGenre() }
                )
            }
            .padding(.top, 36)
            .opacity(genreControlsVisible || reduceMotion ? 1 : 0)
            .offset(y: genreControlsVisible || reduceMotion ? 0 : 10)
            .animation(
                reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.55),
                value: genreControlsVisible
            )
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            resetGenreRevealState()
        }
    }

    private func resetGenreRevealState() {
        visibleGenreChipCount = reduceMotion ? genreChipCount : 0
        genreControlsVisible = reduceMotion
    }

    private func startGenreChipReveal() {
        guard !reduceMotion else {
            visibleGenreChipCount = genreChipCount
            genreControlsVisible = true
            return
        }

        visibleGenreChipCount = 0
        genreControlsVisible = false

        Task { @MainActor in
            for index in 1...genreChipCount {
                try? await Task.sleep(for: .milliseconds(OnboardingMotion.genreChipStaggerDelayMs))
                guard !Task.isCancelled else { return }
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: OnboardingMotion.genreChipFadeDuration)) {
                    visibleGenreChipCount = index
                }
            }

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.55)) {
                genreControlsVisible = true
            }
        }
    }

    private func isGenreChipVisible(_ index: Int) -> Bool {
        reduceMotion || index < visibleGenreChipCount
    }

    @ViewBuilder
    private func animatedGenreChip(index: Int, genre: OnboardingGenreOption) -> some View {
        SeamlessGenreChip(
            title: genre.title,
            symbolName: genre.symbolName,
            isSelected: coordinator.state.worldGenre == genre.id,
            action: { coordinator.selectGenre(genre.id) }
        )
        .opacity(isGenreChipVisible(index) ? 1 : 0)
        .offset(y: isGenreChipVisible(index) ? 0 : 8)
        .allowsHitTesting(isGenreChipVisible(index))
    }

    @ViewBuilder
    private func genreRow(_ options: [OnboardingGenreOption], startIndex: Int) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            ForEach(Array(options.enumerated()), id: \.element.id) { offset, genre in
                animatedGenreChip(index: startIndex + offset, genre: genre)
            }
            Spacer(minLength: 0)
        }
    }

    private var genreTitleSize: CGFloat {
        #if os(iOS)
        26
        #else
        32
        #endif
    }

    // MARK: - Step 5: World name

    private var worldNameScreen: some View {
        VStack(spacing: 0) {
            SeamlessWorldNameField(
                text: $coordinator.worldNameDraft,
                onSubmit: submitWorldName,
                onPromptComplete: { worldNameControlsVisible = true }
            )
            .frame(maxWidth: 900)
            .padding(.horizontal, 24)

            HStack(spacing: 8) {
                SeamlessGhostButton(title: OnboardingCopy.backButton) {
                    coordinator.goBack()
                }
                SeamlessPrimaryButton(
                    title: OnboardingCopy.continueButton,
                    enabled: coordinator.resolvedWorldName != nil,
                    fullWidth: false,
                    action: submitWorldName
                )
            }
            .padding(.top, 40)
            .opacity(worldNameControlsVisible || reduceMotion ? 1 : 0)
            .offset(y: worldNameControlsVisible || reduceMotion ? 0 : 10)
            .animation(
                reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.55),
                value: worldNameControlsVisible
            )

            SeamlessSkipButton(title: OnboardingCopy.openExistingVault) {
                coordinator.trackOpenExistingVault()
                openExistingVault()
            }
            .padding(.top, 32)
            .opacity(worldNameControlsVisible || reduceMotion ? 1 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.06),
                value: worldNameControlsVisible
            )
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            worldNameControlsVisible = reduceMotion
        }
    }

    // MARK: - Step 7: Building

    private var buildingScreen: some View {
        SeamlessBuildingMoment(
            worldName: coordinator.state.worldName,
            onFinished: { coordinator.advanceFromBuilding() }
        )
    }

    // MARK: - Step 8: World ready

    private var worldReadyScreen: some View {
        SeamlessStepShell(
            title: OnboardingCopy.worldReadyTitle(worldName: coordinator.state.worldName),
            subtitle: OnboardingCopy.worldReadySubtitle
        ) {
            SeamlessPrimaryButton(
                title: OnboardingCopy.continueButton,
                action: finishFromWorldReady
            )
        }
    }

    // MARK: - Actions

    private func submitDisplayName() {
        guard coordinator.resolvedDisplayName != nil else { return }
        coordinator.submitDisplayName()
    }

    private func submitWorldName() {
        guard coordinator.resolvedWorldName != nil else { return }
        coordinator.submitWorldName()

        coordinator.analytics.track(.sampleWorldStarted, properties: [
            "goals": coordinator.state.selectedGoals.map(\.rawValue).joined(separator: ","),
            "genre": coordinator.state.worldGenre?.rawValue ?? "unknown",
        ])

        let displayName = coordinator.state.worldName ?? OnboardingCopy.defaultWorldName
        let welcome = OnboardingCopy.welcomeNoteContent(for: coordinator.state, worldName: displayName)
        workspace.bootstrapOnboardingVaultIfNeeded(worldName: displayName, welcomeContent: welcome)
        guard workspace.activeVault != nil else { return }

        applyOnboardingWorldCustomizations(fastLane: false)
        coordinator.usesExistingVault = false
        coordinator.goToWorldReady(trackBuildingComplete: true)
    }

    private func openExistingVault() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a dedicated vault folder — not Documents, Desktop, or your Home folder."
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            let bookmark = VaultSecurityAccess.createBookmark(for: url)
            workspace.openVault(at: url, bookmarkData: bookmark)
            coordinator.analytics.track(.vaultOpened)
            coordinator.usesExistingVault = true
            coordinator.goToWorldReady()
        }
        #else
        folderPickerPurpose = .openVault
        #endif
    }

    #if os(iOS)
    private func handleFolderImport(_ url: URL, for purpose: VaultFolderPickerPurpose) {
        _ = url.startAccessingSecurityScopedResource()

        switch purpose {
        case .openVault:
            workspace.openVault(at: url, bookmarkData: VaultSecurityAccess.createBookmark(for: url))
            coordinator.analytics.track(.vaultOpened)
            coordinator.usesExistingVault = true
            coordinator.goToWorldReady()
        case .createLocation, .reconnectVault:
            break
        }
    }
    #endif

    private func finishFromWorldReady() {
        guard workspace.activeVault != nil else {
            workspace.reportVaultError(
                title: "Choose a vault first",
                message: "Create or open a vault before continuing."
            )
            coordinator.returnToWorldName()
            return
        }

        coordinator.advanceFromWorldReady()
        coordinator.completeOnboarding(fastLane: coordinator.usesExistingVault)
        persistAndExit()
    }

    private func applyOnboardingWorldCustomizations(fastLane: Bool) {
        let displayName = coordinator.state.worldName ?? OnboardingCopy.defaultWorldName

        if let vaultURL = workspace.activeVaultURL {
            _ = try? VaultFilesystem.seedOnboardingSampleContent(
                vaultURL: vaultURL,
                worldName: displayName,
                creatorType: coordinator.state.inferredCreatorType()
            )
            workspace.reloadActiveVaultFromDisk()
            workspace.openFirstCanvasIfAvailable()
            if !fastLane, coordinator.state.inferredCoreDesire() == .finish {
                OnboardingPersistence.requestAutoPlayTimelapse()
            }
        }
    }

    private func persistAndExit() {
        if isPreview {
            onComplete()
            return
        }
        do {
            try WorkspacePersistence.save(workspace.persistedState())
            onComplete()
        } catch {
            workspace.reportVaultError(
                title: "Couldn't save workspace",
                message: error.localizedDescription
            )
        }
    }
}
