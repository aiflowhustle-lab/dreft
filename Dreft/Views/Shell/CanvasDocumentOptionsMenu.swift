import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CanvasDocumentOptionsMenu: View {
    @Bindable var workspace: WorkspaceStore
    @Bindable var canvasStore: CanvasStore
    var entitlements: EntitlementManager
    let fileID: String
    var onSplitRight: () -> Void = {}
    var onSplitDown: () -> Void = {}
    var onImportCanvasBundle: ((URL) -> Void)? = nil
    @Binding var sidebarVisible: Bool
    @Binding var sidebarPanel: SidebarPanel

    @State private var showDeleteConfirm = false
    @State private var showBacklinksSheet = false
    @State private var showOutgoingSheet = false
    @State private var showVersionHistory = false
    @State private var showImageExport = false
    @State private var showBundleImport = false
    #if os(iOS)
    @State private var pendingBundleExport: IOSPendingFileExport?
    #endif

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
                entitlements.performWrite { revealAndRename() }
            }

            Menu("Move file to...") {
                if file?.parentFolderID != nil {
                    Button("Vault root") {
                        entitlements.performWrite { workspace.moveFile(fileID, toFolder: nil) }
                    }
                }
                ForEach(workspace.availableMoveDestinations(for: fileID)) { folder in
                    Button(folder.name) {
                        entitlements.performWrite { workspace.moveFile(fileID, toFolder: folder.id) }
                    }
                }
            }

            Button(workspace.isBookmarked(fileID) ? "Edit bookmark" : "Add bookmark") {
                entitlements.performWrite { workspace.presentBookmarkEditor(for: fileID) }
            }

            Button("Export as image") {
                showImageExport = true
            }

            Button("Export canvas bundle") {
                entitlements.performWrite { exportCanvasBundle() }
            }

            Button("Import canvas bundle") {
                entitlements.performWrite { showBundleImport = true }
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
                entitlements.performWrite { showDeleteConfirm = true }
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
                entitlements: entitlements,
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
        .fileImporter(
            isPresented: $showBundleImport,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                onImportCanvasBundle?(url)
            case .failure(let error):
                workspace.reportVaultError(
                    title: "Import failed",
                    message: error.localizedDescription
                )
            }
        }
        #if os(iOS)
        .fullScreenCover(item: $pendingBundleExport) { pending in
            IOSFileExportPicker(fileURL: pending.url) { _ in
                try? FileManager.default.removeItem(at: pending.url)
                pendingBundleExport = nil
            }
            .ignoresSafeArea()
            .background(Color.clear)
        }
        #endif
    }

    private func revealAndRename() {
        sidebarPanel = .files
        sidebarVisible = true
        workspace.beginInlineRename(for: fileID)
    }

    private func exportCanvasBundle() {
        guard let vaultURL = workspace.activeVaultURL else {
            workspace.reportVaultError(
                title: "No vault available",
                message: VaultErrorMessages.noActiveVault
            )
            return
        }

        let canvasName = file?.name ?? "Canvas"
        let snapshot = canvasStore.documentSnapshot

        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose where to save the canvas bundle folder."
        panel.nameFieldStringValue = "\(canvasName).\(CanvasBundleTransfer.bundleExtension)"
        guard panel.runModal() == .OK, let parentURL = panel.url else { return }

        let bundleURL = parentURL.appendingPathComponent(
            "\(canvasName).\(CanvasBundleTransfer.bundleExtension)",
            isDirectory: true
        )
        do {
            try CanvasBundleTransfer.exportBundle(
                snapshot: snapshot,
                canvasName: canvasName,
                vaultURL: vaultURL,
                to: bundleURL
            )
            NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
        } catch {
            workspace.reportVaultError(title: "Export failed", message: error.localizedDescription)
        }
        #else
        let exportName = "\(sanitizedBundleName(canvasName)).\(CanvasBundleTransfer.bundleExtension)"
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportName, isDirectory: true)
        do {
            try CanvasBundleTransfer.exportBundle(
                snapshot: snapshot,
                canvasName: canvasName,
                vaultURL: vaultURL,
                to: bundleURL
            )
            pendingBundleExport = IOSPendingFileExport(url: bundleURL)
        } catch {
            workspace.reportVaultError(title: "Export failed", message: error.localizedDescription)
        }
        #endif
    }

    private func sanitizedBundleName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Canvas" : cleaned
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
            entitlements: entitlements,
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
    var entitlements: EntitlementManager
    let documentTitle: String

    @State private var sidebarVisible = false
    @State private var sidebarPanel: SidebarPanel = .files

    var body: some View {
        InfiniteCanvasView(
            store: canvasStore,
            workspace: workspace,
            entitlements: entitlements,
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
