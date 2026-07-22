import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CanvasDocumentOptionsMenu: View {
    @Bindable var workspace: WorkspaceStore
    @Bindable var canvasStore: CanvasStore
    let fileID: String
    var onSplitRight: () -> Void = {}
    var onSplitDown: () -> Void = {}
    @Binding var sidebarVisible: Bool
    @Binding var sidebarPanel: SidebarPanel

    @State private var showDeleteConfirm = false
    @State private var showBacklinksSheet = false
    @State private var showOutgoingSheet = false
    @State private var showVersionHistory = false
    @State private var showImageExport = false

    private var file: WorkspaceFileEntry? {
        workspace.files.first { $0.id == fileID }
    }

    var body: some View {
        Menu {
            Button("Split right", action: onSplitRight)
            Button("Split down", action: onSplitDown)
            #if os(macOS)
            Button("Open in new window") {
                openInNewWindow()
            }
            #endif

            Divider()

            Button("Rename...") {
                revealAndRename()
            }

            Menu("Move file to...") {
                if file?.parentFolderID != nil {
                    Button("Vault root") {
                        workspace.moveFile(fileID, toFolder: nil)
                    }
                }
                ForEach(workspace.availableMoveDestinations(for: fileID)) { folder in
                    Button(folder.name) {
                        workspace.moveFile(fileID, toFolder: folder.id)
                    }
                }
            }

            Button(workspace.isBookmarked(fileID) ? "Edit bookmark" : "Add bookmark") {
                workspace.presentBookmarkEditor(for: fileID)
            }

            Button("Export as image") {
                showImageExport = true
            }

            Divider()

            Menu("Copy path") {
                Button("from vault folder") {
                    copyToPasteboard(workspace.vaultRelativePath(for: fileID))
                }
                Button("from system root") {
                    copyToPasteboard(workspace.diskPath(for: fileID))
                }
            }

            Divider()

            Button("Open version history") {
                showVersionHistory = true
            }

            Menu("Open linked view") {
                Button("Open local graph") {
                    workspace.openGraphTab()
                }
                Button("Open backlinks") {
                    showBacklinksSheet = true
                }
                Button("Open outgoing links") {
                    showOutgoingSheet = true
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
                sidebarPanel = .files
                sidebarVisible = true
                workspace.revealInNavigation(fileID)
            }

            Divider()

            Button("Delete file", role: .destructive) {
                showDeleteConfirm = true
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
        .confirmationDialog(
            "Delete \"\(file?.name ?? "this canvas")\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                workspace.deleteFile(fileID)
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showBacklinksSheet) {
            NoteLinkedLinksSheet(workspace: workspace, fileID: fileID, mode: .backlinks)
        }
        .sheet(isPresented: $showOutgoingSheet) {
            NoteLinkedLinksSheet(workspace: workspace, fileID: fileID, mode: .outgoing)
        }
        .sheet(isPresented: $showVersionHistory) {
            CanvasVersionHistorySheet(
                workspace: workspace,
                canvasStore: canvasStore,
                fileID: fileID
            )
        }
        .sheet(isPresented: $showImageExport) {
            CanvasImageExportSheet(
                workspace: workspace,
                canvasStore: canvasStore,
                fileID: fileID
            )
        }
    }

    private func revealAndRename() {
        sidebarPanel = .files
        sidebarVisible = true
        workspace.beginInlineRename(for: fileID)
    }

    private func copyToPasteboard(_ value: String?) {
        guard let value, !value.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }

    #if os(macOS)
    private func openInNewWindow() {
        let content = CanvasStandaloneWindowView(
            workspace: workspace,
            canvasStore: canvasStore,
            documentTitle: file?.name ?? "Canvas"
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = file?.name ?? "Canvas"
        window.contentView = NSHostingView(rootView: content)
        window.center()
        let controller = NSWindowController(window: window)
        CanvasStandaloneWindowRegistry.controllers.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openInDefaultApp() {
        guard let path = workspace.diskPath(for: fileID) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func revealInFinder() {
        guard let path = workspace.diskPath(for: fileID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    #else
    private func openInNewWindow() {
        workspace.reportVaultError(
            title: "Open in new window",
            message: "Separate canvas windows are available on macOS."
        )
    }

    private func openInDefaultApp() {
        guard let path = workspace.diskPath(for: fileID) else { return }
        UIApplication.shared.open(URL(fileURLWithPath: path))
    }
    #endif
}

#if os(macOS)
private enum CanvasStandaloneWindowRegistry {
    static var controllers: [NSWindowController] = []
}

private struct CanvasStandaloneWindowView: View {
    @Bindable var workspace: WorkspaceStore
    @Bindable var canvasStore: CanvasStore
    let documentTitle: String

    @State private var sidebarVisible = false
    @State private var sidebarPanel: SidebarPanel = .files

    var body: some View {
        InfiniteCanvasView(
            store: canvasStore,
            workspace: workspace,
            sidebarVisible: $sidebarVisible,
            sidebarPanel: $sidebarPanel,
            documentTitle: documentTitle,
            vaultURL: workspace.activeVaultURL
        )
        .frame(minWidth: 640, minHeight: 420)
        .background(AppColors.canvasBackground)
    }
}
#endif
