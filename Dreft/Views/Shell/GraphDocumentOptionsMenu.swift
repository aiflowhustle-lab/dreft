import SwiftUI

extension Notification.Name {
    static let graphCopyScreenshot = Notification.Name("graphCopyScreenshot")
}

struct GraphDocumentOptionsMenu: View {
    @Bindable var workspace: WorkspaceStore
    var entitlements: EntitlementManager
    let paneID: String
    var onSplitRight: () -> Void = {}
    var onSplitDown: () -> Void = {}
    var bookmarkFileID: String?

    var body: some View {
        Menu {
            Button("Split right", action: onSplitRight)
            Button("Split down", action: onSplitDown)

            Divider()

            Button("Copy screenshot") {
                NotificationCenter.default.post(
                    name: .graphCopyScreenshot,
                    object: nil,
                    userInfo: ["paneID": paneID]
                )
            }

            if let bookmarkFileID {
                Button {
                    entitlements.performWrite {
                        workspace.presentBookmarkEditor(for: bookmarkFileID)
                    }
                } label: {
                    if workspace.isBookmarked(bookmarkFileID) {
                        Label("Bookmark...", systemImage: "checkmark")
                    } else {
                        Text("Bookmark...")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More options")
        .accessibilityLabel("More options")
    }
}
