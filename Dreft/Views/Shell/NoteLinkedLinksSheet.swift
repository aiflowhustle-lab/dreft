import SwiftUI

enum NoteLinkedLinksMode {
    case backlinks
    case outgoing

    var title: String {
        switch self {
        case .backlinks: "Backlinks"
        case .outgoing: "Outgoing links"
        }
    }

    var emptyMessage: String {
        switch self {
        case .backlinks: "No notes link to this file yet."
        case .outgoing: "This note doesn't link anywhere yet."
        }
    }
}

struct NoteLinkedLinksSheet: View {
    @Bindable var workspace: WorkspaceStore
    let fileID: String
    let mode: NoteLinkedLinksMode
    @Environment(\.dismiss) private var dismiss

    private var linkedFiles: [WorkspaceFileEntry] {
        let ids = switch mode {
        case .backlinks: workspace.incomingLinkIDs(for: fileID)
        case .outgoing: workspace.outgoingLinkIDs(for: fileID)
        }
        return ids.compactMap { id in workspace.files.first(where: { $0.id == id }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.selectionStroke)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(AppColors.borderSubtle)

            if linkedFiles.isEmpty {
                Text(mode.emptyMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(linkedFiles) { file in
                            Button {
                                workspace.selectFile(file.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(file.name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    if let badge = file.badge {
                                        Text(badge)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(AppColors.textMuted)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 240)
        .background(AppColors.canvasBackground)
    }
}
