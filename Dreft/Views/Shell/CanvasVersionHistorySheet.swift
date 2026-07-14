import SwiftUI

struct CanvasVersionHistorySheet: View {
    @Bindable var workspace: WorkspaceStore
    @Bindable var canvasStore: CanvasStore
    let fileID: String

    @Environment(\.dismiss) private var dismiss
    @State private var versions: [CanvasFileVersion] = []

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
                            restore(record)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .onAppear(perform: loadVersions)
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

    private func restore(_ record: CanvasFileVersion) {
        do {
            let data = try Data(contentsOf: record.url)
            guard case .success(let snapshot) = CanvasDocumentFormat.read(from: data) else {
                workspace.reportVaultError(
                    title: "Restore failed",
                    message: "The selected canvas version is invalid or unsupported."
                )
                return
            }
            canvasStore.restoreDocumentSnapshot(snapshot)
            dismiss()
        } catch {
            workspace.reportVaultError(title: "Restore failed", message: error.localizedDescription)
        }
    }
}

struct CanvasFileVersion: Identifiable {
    let id = UUID()
    let url: URL
    let modifiedAt: Date
    let displayName: String
}
