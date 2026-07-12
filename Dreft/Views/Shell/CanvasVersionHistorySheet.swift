import SwiftUI
#if os(macOS)
import AppKit
#endif

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

            #if os(macOS)
            if versions.isEmpty {
                ContentUnavailableView(
                    "No previous versions",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("macOS has not stored an earlier version of this canvas yet.")
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
            #else
            ContentUnavailableView(
                "Version history unavailable",
                systemImage: "clock.arrow.circlepath",
                description: Text("Canvas version history is currently available on macOS.")
            )
            #endif
        }
        .frame(minWidth: 520, minHeight: 360)
        .onAppear(perform: loadVersions)
    }

    private func loadVersions() {
        #if os(macOS)
        guard let path = workspace.diskPath(for: fileID) else { return }
        let url = URL(fileURLWithPath: path)
        versions = (NSFileVersion.otherVersionsOfItem(at: url) ?? [])
            .map(CanvasFileVersion.init)
            .sorted { $0.modifiedAt > $1.modifiedAt }
        #endif
    }

    private func restore(_ record: CanvasFileVersion) {
        #if os(macOS)
        do {
            let data = try Data(contentsOf: record.url)
            guard case .success(let snapshot) = CanvasDocumentFormat.read(from: data) else {
                workspace.reportVaultError(
                    title: "Restore failed",
                    message: "The selected canvas version is invalid or unsupported."
                )
                return
            }
            canvasStore.applyDocumentSnapshot(snapshot)
            canvasStore.onDidMutate?()
            dismiss()
        } catch {
            workspace.reportVaultError(title: "Restore failed", message: error.localizedDescription)
        }
        #endif
    }
}

#if os(macOS)
struct CanvasFileVersion: Identifiable {
    let id = UUID()
    let url: URL
    let modifiedAt: Date
    let displayName: String

    init(_ version: NSFileVersion) {
        url = version.url
        modifiedAt = version.modificationDate ?? .distantPast
        displayName = version.localizedName ?? "Previous version"
    }
}
#else
struct CanvasFileVersion: Identifiable {
    let id = UUID()
}
#endif
