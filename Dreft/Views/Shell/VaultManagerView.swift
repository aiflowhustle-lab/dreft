import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct VaultManagerView: View {
    @Bindable var workspace: WorkspaceStore
    #if os(iOS)
    var onRequestFolderPicker: ((VaultFolderPickerPurpose, @escaping (URL, VaultFolderPickerPurpose) -> Void) -> Void)? = nil
    #endif
    @State private var screen: Screen = .home
    @State private var newVaultName = ""
    @State private var newVaultLocation = ""
    @State private var createLocationBookmark: Data?
    #if os(iOS)
    @State private var localFolderPickerPurpose: VaultFolderPickerPurpose?
    #endif
    @FocusState private var nameFieldFocused: Bool

    private enum Screen {
        case home
        case createLocal
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        ZStack {
            AppColors.canvasBackground.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    closeManager()
                }

            managerCard
                .overlay(alignment: .topLeading) {
                    closeButton
                        .padding(12)
                }
        }
        .onAppear {
            screen = .home
        }
        #if os(iOS)
        .vaultFolderPicker(purpose: localFolderPickerBinding) { url, purpose in
            handleFolderImport(url, for: purpose)
        }
        #endif
    }

    #if os(iOS)
    private var localFolderPickerBinding: Binding<VaultFolderPickerPurpose?> {
        if onRequestFolderPicker != nil {
            Binding(
                get: { nil },
                set: { _ in }
            )
        } else {
            $localFolderPickerPurpose
        }
    }

    private func requestFolderPicker(_ purpose: VaultFolderPickerPurpose) {
        if let onRequestFolderPicker {
            onRequestFolderPicker(purpose, handleFolderImport)
        } else {
            localFolderPickerPurpose = purpose
        }
    }
    #endif

    private var managerCard: some View {
        HStack(spacing: 0) {
            vaultListPanel
            mainPanel
        }
        #if os(iOS)
        .frame(maxWidth: 680, maxHeight: 620)
        .padding(.horizontal, 20)
        #else
        .frame(width: 710, height: 560)
        #endif
        .background(AppColors.overlayPanel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.floatingChromeShadow, radius: 40, y: 18)
        .onTapGesture { }
    }

    @ViewBuilder
    private var closeButton: some View {
        #if os(macOS)
        trafficLights
        #else
        Button {
            closeManager()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(AppColors.sidebarSelection))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close vault manager")
        #endif
    }

    #if os(macOS)
    private var trafficLights: some View {
        HStack(spacing: 8) {
            Button {
                closeManager()
            } label: {
                Circle()
                    .fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .help("Close")

            Circle()
                .fill(Color(red: 1.0, green: 0.74, blue: 0.18))
                .frame(width: 12, height: 12)
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 12, height: 12)
        }
    }
    #endif

    private var vaultListPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer().frame(height: 40)

            ForEach(workspace.vaults) { vault in
                vaultRow(vault)
            }

            Spacer()
        }
        #if os(iOS)
        .frame(maxWidth: 220)
        #else
        .frame(width: 250)
        #endif
        .frame(maxHeight: .infinity)
        .background(AppColors.shellBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(width: 1)
        }
    }

    private func vaultRow(_ vault: WorkspaceVault) -> some View {
        let isActive = vault.id == workspace.activeVault?.id
        let accessIssue = workspace.vaultAccessibilityIssue(for: vault)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(vault.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    if accessIssue != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.orange)
                            .accessibilityLabel("Needs reconnection")
                    }
                }
                Text(accessIssue ?? vault.path)
                    .font(.system(size: 11))
                    .foregroundStyle(accessIssue != nil ? Color.orange : AppColors.textMuted)
                    .lineLimit(accessIssue == nil ? 1 : 2)
                    .truncationMode(.middle)
            }
            Spacer()
            Menu {
                if accessIssue != nil {
                    Button("Reconnect folder...") {
                        reconnectVaultFolder(vault.id)
                    }
                    Divider()
                }
                Button("Remove from list") {
                    workspace.removeVault(vault.id)
                }
                .disabled(workspace.vaults.count <= 1)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Vault options")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? AppColors.sidebarSelection : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.switchVault(vault.id)
        }
        .padding(.horizontal, 10)
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            DreftAppMark(cornerRadius: 18)
                .frame(width: 88, height: 88)

            Spacer().frame(height: 16)

            Text("Dreft")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Version \(appVersion)")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textMuted)
                .padding(.top, 2)

            Spacer().frame(height: 28)

            switch screen {
            case .home:
                homeSection
            case .createLocal:
                createLocalSection
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var homeSection: some View {
        VStack(spacing: 0) {
            actionRow(
                title: "Create new vault",
                subtitle: createVaultSubtitle,
                buttonTitle: "Create",
                isPrimary: true
            ) {
                newVaultName = ""
                newVaultLocation = ""
                createLocationBookmark = nil
                withAnimation(.easeOut(duration: 0.12)) { screen = .createLocal }
            }

            hairline

            actionRow(
                title: "Open folder as vault",
                subtitle: openFolderVaultSubtitle,
                buttonTitle: "Open",
                isPrimary: false
            ) {
                openFolderAsVault()
            }

            hairline

            AppearanceSettingsSection()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.sidebarSelection.opacity(0.65))
        )
        .padding(.horizontal, 32)
    }

    private var createVaultSubtitle: String {
        #if os(iOS)
        "Name your vault and store it on this iPad, or browse to a folder you choose."
        #else
        "Name your vault and store it in app storage, or choose any folder."
        #endif
    }

    private var openFolderVaultSubtitle: String {
        #if os(iOS)
        "Pick a folder in Files. Dreft keeps access so your notes stay on this device."
        #else
        "Choose a dedicated folder — not your entire Documents or Home folder."
        #endif
    }

    private var canCreateVault: Bool {
        !newVaultName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private var createLocalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) { screen = .home }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(AppColors.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 10)

            Text("Create local vault")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Spacer().frame(height: 14)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vault name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Pick a name for your awesome vault.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppColors.textMuted)
                    }

                    Spacer()

                    TextField("Vault name", text: $newVaultName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppColors.textPrimary)
                        .focused($nameFieldFocused)
                        .frame(width: 150)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppColors.sidebarSelection)
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
                        .onSubmit { createVault() }
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

            Spacer().frame(height: 18)

            HStack {
                Spacer()
                Button(action: createVault) {
                    Text("Create")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    AppColors.selectionStroke
                                        .opacity(canCreateVault ? 1 : 0.35)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canCreateVault)
                Spacer()
            }
        }
        .padding(.horizontal, 32)
        .onAppear { nameFieldFocused = true }
    }

    private var locationDescription: String {
        if newVaultLocation.isEmpty {
            return defaultLocationDescription
        }
        return newVaultLocation
    }

    private var defaultParentDirectory: URL {
        VaultFilesystem.appContainerVaultsDirectory()
    }

    private var defaultLocationDescription: String {
        #if os(iOS)
        "On My iPad / Dreft / Vaults"
        #else
        "Dreft / Vaults (app storage)"
        #endif
    }

    private func closeManager() {
        withAnimation(.easeOut(duration: 0.15)) {
            workspace.isVaultManagerOpen = false
        }
        screen = .home
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
            closeManager()
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
            closeManager()
        }
        #else
        requestFolderPicker(.openVault)
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
        requestFolderPicker(.createLocation)
        #endif
    }

    #if os(iOS)
    private func handleFolderImport(_ url: URL, for purpose: VaultFolderPickerPurpose) {
        _ = url.startAccessingSecurityScopedResource()

        switch purpose {
        case .openVault:
            let bookmark = VaultSecurityAccess.createBookmark(for: url)
            workspace.openVault(at: url, bookmarkData: bookmark)
            closeManager()
        case .createLocation:
            newVaultLocation = url.path
            createLocationBookmark = VaultSecurityAccess.createBookmark(for: url)
        case .reconnectVault(let vaultID):
            let bookmark = VaultSecurityAccess.createBookmark(for: url)
            workspace.reconnectVault(vaultID, at: url, bookmarkData: bookmark)
        }
    }
    #endif

    private func reconnectVaultFolder(_ vaultID: String) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Reconnect"
        panel.message = "Choose the vault folder again to restore access."
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            let bookmark = VaultSecurityAccess.createBookmark(for: url)
            workspace.reconnectVault(vaultID, at: url, bookmarkData: bookmark)
        }
        #else
        requestFolderPicker(.reconnectVault(vaultID: vaultID))
        #endif
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func actionRow(
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
            }

            Spacer()

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isPrimary ? .white : AppColors.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isPrimary ? AppColors.selectionStroke : AppColors.sidebarSelection)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        isPrimary ? Color.clear : AppColors.border,
                                        lineWidth: 1
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

}
