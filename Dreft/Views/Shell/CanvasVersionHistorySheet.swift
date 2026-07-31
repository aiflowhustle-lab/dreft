import SwiftUI

struct CanvasVersionHistorySheet: View {
    @Bindable var workspace: WorkspaceStore
    @Bindable var canvasStore: CanvasStore
    var entitlements: EntitlementManager
    let fileID: String

    @Environment(\.dismiss) private var dismiss
    @State private var versions: [CanvasFileVersion] = []
    @State private var missingAssetRestore: MissingAssetRestorePrompt?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Version history")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(16)

            Divider()

            if versions.isEmpty {
                ContentUnavailableView(
                    "No previous versions",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No earlier version of this canvas has been stored yet.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(versions) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.modifiedAt.formatted(date: .abbreviated, time: .standard))
                                .font(.system(size: 13, weight: .medium))
                            Text(record.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Button("Restore") {
                            beginRestore(record)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .onAppear(perform: loadVersions)
        .alert(item: $missingAssetRestore) { prompt in
            Alert(
                title: Text("Missing images"),
                message: Text(prompt.message),
                primaryButton: .destructive(Text("Restore anyway")) {
                    applyRestore(prompt.snapshot)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func loadVersions() {
        guard let vaultURL = workspace.activeVaultURL,
              let file = workspace.files.first(where: { $0.id == fileID }) else { return }
        let dir = VaultFilesystem.canvasVersionsDirectory(
            forRelativePath: file.relativePath,
            vaultURL: vaultURL
        )
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        versions = urls
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return CanvasFileVersion(url: url, modifiedAt: date, displayName: "Previous version")
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func beginRestore(_ record: CanvasFileVersion) {
        guard entitlements.requireWriteAccess() else { return }
        do {
            let data = try Data(contentsOf: record.url)
            guard case .success(let snapshot) = CanvasDocumentFormat.read(from: data) else {
                workspace.reportVaultError(
                    title: "Restore failed",
                    message: "The selected canvas version is invalid or unsupported."
                )
                return
            }

            if let vaultURL = workspace.activeVaultURL {
                let missing = VaultFilesystem.missingCanvasAssetPaths(in: snapshot, vaultURL: vaultURL)
                if !missing.isEmpty {
                    missingAssetRestore = MissingAssetRestorePrompt(snapshot: snapshot, missingCount: missing.count)
                    return
                }
            }

            applyRestore(snapshot)
        } catch {
            workspace.reportVaultError(title: "Restore failed", message: error.localizedDescription)
        }
    }

    private func applyRestore(_ snapshot: CanvasDocumentSnapshot) {
        canvasStore.restoreDocumentSnapshot(snapshot)
        dismiss()
    }
}

private struct MissingAssetRestorePrompt: Identifiable {
    let id = UUID()
    let snapshot: CanvasDocumentSnapshot
    let missingCount: Int

    var message: String {
        if missingCount == 1 {
            return "This version references 1 image that is no longer in the vault. Restoring will leave that image broken."
        }
        return "This version references \(missingCount) images that are no longer in the vault. Restoring will leave those images broken."
    }
}

struct CanvasFileVersion: Identifiable {
    let id = UUID()
    let url: URL
    let modifiedAt: Date
    let displayName: String
}
