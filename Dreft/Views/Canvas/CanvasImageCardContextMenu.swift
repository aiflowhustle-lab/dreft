import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct CanvasImageCardContextMenu: View {
    @Bindable var workspace: WorkspaceStore
    @Bindable var store: CanvasStore
    let card: CanvasCard
    @Binding var sidebarVisible: Bool
    @Binding var sidebarPanel: SidebarPanel

    var onZoom: () -> Void
    var onSwap: () -> Void
    var onRemove: () -> Void
    var onRename: () -> Void

    private var linkedFileID: String? {
        workspace.fileID(forRelativePath: card.content)
    }

    private var relativePath: String? {
        store.imageRelativePath(for: card)
    }

    private var absolutePath: String? {
        store.imageFileURL(for: card)?.path
    }

    var body: some View {
        Button("Zoom to selection", action: onZoom)

        Button("Swap file...", action: onSwap)

        Button("Open in new window") {
            openInNewWindow()
        }

        Divider()

        Button("Rename...") {
            onRename()
        }

        if let linkedFileID {
            moveFileMenu(fileID: linkedFileID)

            Button {
                workspace.presentBookmarkEditor(for: linkedFileID)
            } label: {
                if workspace.isBookmarked(linkedFileID) {
                    Label("Bookmark...", systemImage: "checkmark")
                } else {
                    Text("Bookmark...")
                }
            }
        }

        Divider()

        Button("Open in default app") {
            openInDefaultApp()
        }

        #if os(macOS)
        Button("Reveal in Finder") {
            revealInFinder()
        }
        #endif

        Button("Reveal file in navigation") {
            revealInNavigation()
        }

        Divider()

        Button("Remove", role: .destructive, action: onRemove)

        Divider()

        Menu("Copy path") {
            if let path = relativePath {
                Button("from vault folder") {
                    copyToPasteboard(path)
                }
            }

            if let path = absolutePath {
                Button("from system root") {
                    copyToPasteboard(path)
                }
            }
        }
    }

    @ViewBuilder
    private func moveFileMenu(fileID: String) -> some View {
        Menu("Move file to...") {
            if workspace.files.first(where: { $0.id == fileID })?.parentFolderID != nil {
                Button("Vault root") {
                    workspace.moveFile(fileID, toFolder: nil)
                }
            }
            ForEach(workspace.availableMoveDestinations(for: fileID)) { folder in
                if folder.id != workspace.files.first(where: { $0.id == fileID })?.parentFolderID {
                    Button(folder.name) {
                        workspace.moveFile(fileID, toFolder: folder.id)
                    }
                }
            }
        }
    }

    private func revealInNavigation() {
        sidebarPanel = .files
        sidebarVisible = true
        if let linkedFileID {
            workspace.revealInNavigation(linkedFileID)
        } else if let path = relativePath, let fileID = workspace.fileID(forRelativePath: path) {
            workspace.revealInNavigation(fileID)
        }
    }

    private func copyToPasteboard(_ string: String?) {
        guard let string, !string.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    #if os(macOS)
    private func revealInFinder() {
        guard let url = store.imageFileURL(for: card) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openInDefaultApp() {
        guard let url = store.imageFileURL(for: card) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openInNewWindow() {
        workspace.reportVaultError(
            title: "New window",
            message: "Opening images in a separate window isn't supported yet."
        )
    }
    #else
    private func openInDefaultApp() {
        guard let url = store.imageFileURL(for: card) else { return }
        UIApplication.shared.open(url)
    }

    private func openInNewWindow() {
        workspace.reportVaultError(
            title: "New window",
            message: "Opening images in a separate window isn't supported on iPad yet."
        )
    }
    #endif
}
