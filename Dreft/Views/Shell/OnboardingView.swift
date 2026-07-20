import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var workspace = WorkspaceStore()
    @State private var step: Step = .welcome
    @State private var vaultScreen: VaultScreen = .choices
    @State private var newVaultName = "My Vault"
    @State private var newVaultLocation = ""
    @State private var createLocationBookmark: Data?
    @State private var tourPage = 0
    #if os(iOS)
    @State private var showOpenFolderImporter = false
    @State private var showCreateLocationImporter = false
    #endif
    @FocusState private var nameFieldFocused: Bool

    private enum Step {
        case welcome
        case vault
        case tour
    }

    private enum VaultScreen {
        case choices
        case create
    }

    #if os(iOS)
    private enum FolderImportPurpose {
        case openVault
        case createLocation
    }
    #endif

    var body: some View {
        ZStack {
            AppColors.canvasBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .vaultErrorAlert(workspace: workspace)
        #if os(iOS)
        .fileImporter(
            isPresented: $showOpenFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result, for: .openVault)
        }
        .fileImporter(
            isPresented: $showCreateLocationImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result, for: .createLocation)
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .vault:
            vaultStep
        case .tour:
            tourStep
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            DreftAppMark(cornerRadius: 20)
                .frame(width: 96, height: 96)

            Spacer().frame(height: 20)

            Text("Dreft")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Local notes and infinite canvas.\nYour data stays on your device.")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 12)

            Spacer().frame(height: 28)

            AppearanceSettingsSection()
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.sidebarSelection.opacity(0.65))
                )

            Spacer()

            primaryButton("Continue") {
                withAnimation(.easeOut(duration: 0.18)) {
                    step = .vault
                }
            }
        }
    }

    // MARK: - Vault

    @ViewBuilder
    private var vaultStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "Your vault",
                subtitle: "Notes and canvases live in a folder you choose."
            )

            Spacer().frame(height: 24)

            switch vaultScreen {
            case .choices:
                vaultChoices
            case .create:
                createVaultForm
            }

            Spacer()
        }
    }

    private var vaultChoices: some View {
        VStack(spacing: 0) {
            vaultActionRow(
                title: "Try Dreft",
                subtitle: "Create a sample vault with a welcome note.",
                buttonTitle: "Start",
                isPrimary: true
            ) {
                tryQuickStart()
            }

            hairline

            vaultActionRow(
                title: "Create new vault",
                subtitle: createVaultSubtitle,
                buttonTitle: "Create",
                isPrimary: false
            ) {
                newVaultName = "My Vault"
                newVaultLocation = ""
                createLocationBookmark = nil
                withAnimation(.easeOut(duration: 0.12)) {
                    vaultScreen = .create
                }
            }

            hairline

            vaultActionRow(
                title: "Open folder as vault",
                subtitle: "Use an existing Obsidian-style vault folder.",
                buttonTitle: "Open",
                isPrimary: false
            ) {
                openFolderAsVault()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.sidebarSelection.opacity(0.65))
        )
    }

    private var createVaultForm: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vault name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        TextField("My Vault", text: $newVaultName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AppColors.inputFieldBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                nameFieldFocused
                                                    ? AppColors.selectionStroke.opacity(0.8)
                                                    : AppColors.border,
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .focused($nameFieldFocused)
                            .onSubmit { createVault() }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                hairline

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(locationDescription)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppColors.textMuted)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button(action: browseForLocation) {
                        Text("Browse")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AppColors.sidebarSelection)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.sidebarSelection.opacity(0.65))
            )

            Spacer().frame(height: 16)

            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        vaultScreen = .choices
                    }
                } label: {
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                primaryButton("Create vault", enabled: canCreateVault) {
                    createVault()
                }
            }
        }
        .onAppear { nameFieldFocused = true }
    }

    // MARK: - Tour

    private var tourStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "Quick tour",
                subtitle: "Three places to know — you can explore the rest as you go."
            )

            Spacer().frame(height: 28)

            TabView(selection: $tourPage) {
                tourCard(
                    icon: "sidebar.leading",
                    title: "Sidebar",
                    body: "Browse notes, canvases, and bookmarks. Create files and switch vaults from the footer."
                )
                .tag(0)

                tourCard(
                    icon: "rectangle.on.rectangle.angled",
                    title: "Canvas",
                    body: "Place note and image cards on an infinite board. Connect ideas with lines and labels."
                )
                .tag(1)

                tourCard(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "Graph",
                    body: "See how your notes link together. Open it from the icon rail anytime."
                )
                .tag(2)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 220)
            #else
            .tabViewStyle(.automatic)
            .frame(height: 200)
            #endif

            Spacer()

            HStack {
                Button("Skip") {
                    finishOnboarding()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .buttonStyle(.plain)

                Spacer()

                if tourPage < 2 {
                    primaryButton("Next") {
                        withAnimation { tourPage += 1 }
                    }
                } else {
                    primaryButton("Get started") {
                        finishOnboarding()
                    }
                }
            }
        }
    }

    private func tourCard(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColors.selectionStroke)
                .frame(height: 36)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.sidebarSelection.opacity(0.65))
        )
    }

    // MARK: - Actions

    private func tryQuickStart() {
        workspace.bootstrapDefaultVaultIfNeeded()
        guard workspace.activeVault != nil else { return }
        advanceToTour()
    }

    private func createVault() {
        let name = newVaultName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let parentDirectory = newVaultLocation.isEmpty
            ? defaultParentDirectory.path
            : newVaultLocation

        do {
            try workspace.createVault(
                name: name,
                parentDirectory: parentDirectory,
                parentBookmark: createLocationBookmark
            )
            advanceToTour()
        } catch {
            workspace.reportVaultError(title: "Couldn't create vault", message: error.localizedDescription)
        }
    }

    private func openFolderAsVault() {
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
            advanceToTour()
        }
        #else
        showOpenFolderImporter = true
        #endif
    }

    private func browseForLocation() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            newVaultLocation = url.path
            createLocationBookmark = VaultSecurityAccess.createBookmark(for: url)
        }
        #else
        showCreateLocationImporter = true
        #endif
    }

    #if os(iOS)
    private func handleFolderImport(_ result: Result<[URL], Error>, for purpose: FolderImportPurpose) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        _ = url.startAccessingSecurityScopedResource()

        switch purpose {
        case .openVault:
            let bookmark = VaultSecurityAccess.createBookmark(for: url)
            workspace.openVault(at: url, bookmarkData: bookmark)
            advanceToTour()
        case .createLocation:
            newVaultLocation = url.path
            createLocationBookmark = VaultSecurityAccess.createBookmark(for: url)
        }
    }
    #endif

    private func advanceToTour() {
        guard workspace.activeVault != nil else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            step = .tour
            tourPage = 0
        }
    }

    private func finishOnboarding() {
        guard workspace.activeVault != nil else {
            workspace.reportVaultError(
                title: "Choose a vault first",
                message: "Create or open a vault before continuing."
            )
            withAnimation { step = .vault }
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

    // MARK: - Helpers

    private var createVaultSubtitle: String {
        #if os(iOS)
        "Create a vault in Dreft storage or a folder you choose."
        #else
        "Create a vault in app storage or any folder you choose."
        #endif
    }

    private var canCreateVault: Bool {
        !newVaultName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var defaultParentDirectory: URL {
        VaultFilesystem.appContainerVaultsDirectory()
    }

    private var locationDescription: String {
        if newVaultLocation.isEmpty {
            #if os(iOS)
            return "On My iPad / Dreft / Vaults"
            #else
            return "Dreft / Vaults (app storage)"
            #endif
        }
        return newVaultLocation
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func primaryButton(
        _ title: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.selectionStroke.opacity(enabled ? 1 : 0.35))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func vaultActionRow(
        title: String,
        subtitle: String,
        buttonTitle: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isPrimary ? .white : AppColors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isPrimary ? AppColors.selectionStroke : AppColors.sidebarSelection)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isPrimary ? Color.clear : AppColors.border, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
}

private extension View {
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
