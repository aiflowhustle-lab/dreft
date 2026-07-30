import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct CanvasNoteCardContextMenu: View {
    @Bindable var workspace: WorkspaceStore
    @Bindable var store: CanvasStore
    var entitlements: EntitlementManager
    let card: CanvasCard
    @Binding var sidebarVisible: Bool
    @Binding var sidebarPanel: SidebarPanel

    var onZoom: () -> Void
    var onRemove: () -> Void
    var onRename: () -> Void

    private var linkedPath: String? {
        CanvasCardContent.linkedNotePath(for: card)
    }

    private var linkedFileID: String? {
        guard let linkedPath else { return nil }
        return workspace.fileID(forRelativePath: linkedPath)
    }

    private var linkedFileURL: URL? {
        guard let linkedPath, let vaultURL = store.vaultURL else { return nil }
        return vaultURL.appendingPathComponent(linkedPath)
    }

    var body: some View {
        Button("Zoom to selection", action: onZoom)

        if let linkedFileID, let file = workspace.files.first(where: { $0.id == linkedFileID }) {
            Button("Open linked note") {
                workspace.openTab(for: file)
            }

            Divider()
        }

        Button("Rename...") {
            entitlements.performWrite {
                onRename()
            }
        }

        if let linkedFileID {
            moveFileMenu(fileID: linkedFileID)

            Button {
                entitlements.performWrite {
                    workspace.presentBookmarkEditor(for: linkedFileID)
                }
            } label: {
                if workspace.isBookmarked(linkedFileID) {
                    Label("Bookmark...", systemImage: "checkmark")
                } else {
                    Text("Bookmark...")
                }
            }
        }

        if linkedPath != nil {
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
        }

        Divider()

        Button("Remove", role: .destructive, action: onRemove)

        if let linkedPath {
            Divider()

            Menu("Copy path") {
                Button("from vault folder") {
                    copyToPasteboard(linkedPath)
                }

                if let path = linkedFileURL?.path {
                    Button("from system root") {
                        copyToPasteboard(path)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func moveFileMenu(fileID: String) -> some View {
        Menu("Move file to...") {
            if workspace.files.first(where: { $0.id == fileID })?.parentFolderID != nil {
                Button("Vault root") {
                    entitlements.performWrite {
                        workspace.moveFile(fileID, toFolder: nil)
                    }
                }
            }
            ForEach(workspace.availableMoveDestinations(for: fileID)) { folder in
                if folder.id != workspace.files.first(where: { $0.id == fileID })?.parentFolderID {
                    Button(folder.name) {
                        entitlements.performWrite {
                            workspace.moveFile(fileID, toFolder: folder.id)
                        }
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
        } else if let path = linkedPath, let fileID = workspace.fileID(forRelativePath: path) {
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
        guard let url = linkedFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openInDefaultApp() {
        guard let url = linkedFileURL else { return }
        NSWorkspace.shared.open(url)
    }
    #else
    private func openInDefaultApp() {
        guard let url = linkedFileURL else { return }
        UIApplication.shared.open(url)
    }
    #endif
}
