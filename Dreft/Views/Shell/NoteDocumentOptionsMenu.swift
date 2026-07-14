import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NoteDocumentOptionsMenu: View {
    @Bindable var workspace: WorkspaceStore
    let fileID: String
    @Binding var isReading: Bool
    @Binding var splitLayout: NoteSplitLayout
    @Binding var sidebarVisible: Bool
    @Binding var sidebarPanel: SidebarPanel
    @Binding var showFindBar: Bool

    @State private var showDeleteConfirm = false
    @State private var showBacklinksSheet = false
    @State private var showOutgoingSheet = false
    @State private var linkedLinksMode: NoteLinkedLinksMode = .backlinks

    private var file: WorkspaceFileEntry? {
        workspace.files.first { $0.id == fileID }
    }

    var body: some View {
        Menu {
            Button("Backlinks in document") {
                linkedLinksMode = .backlinks
                showBacklinksSheet = true
            }

            Button {
                isReading = true
                splitLayout = .none
            } label: {
                if isReading && splitLayout == .none {
                    Label("Reading view", systemImage: "checkmark")
                } else {
                    Text("Reading view")
                }
            }

            Divider()

            Button("Split right") {
                splitLayout = .right
                isReading = false
            }
            Button("Split down") {
                splitLayout = .down
                isReading = false
            }
            Button("Open in new window") {
                openInNewWindow()
            }

            Divider()

            Button("Rename...") {
                sidebarPanel = .files
                sidebarVisible = true
                workspace.beginInlineRename(for: fileID)
            }

            Menu("Move file to...") {
                Button("Vault root") {
                    workspace.moveFile(fileID, toFolder: nil)
                }
                ForEach(workspace.availableMoveDestinations(for: fileID)) { folder in
                    Button(folder.name) {
                        workspace.moveFile(fileID, toFolder: folder.id)
                    }
                }
            }

            Button {
                workspace.presentBookmarkEditor(for: fileID)
            } label: {
                if workspace.isBookmarked(fileID) {
                    Label("Bookmark...", systemImage: "checkmark")
                } else {
                    Text("Bookmark...")
                }
            }

            Button("Export to PDF...") {
                exportPDF()
            }

            Divider()

            Button("Find...") {
                showFindBar = true
                isReading = false
                splitLayout = .none
            }
            Button("Replace...") {
                showFindBar = true
                isReading = false
                splitLayout = .none
            }
            .disabled(isReading)

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

            Menu("Open linked view") {
                Button("Open local graph") {
                    workspace.openGraphTab()
                }
                Button("Open backlinks") {
                    linkedLinksMode = .backlinks
                    showBacklinksSheet = true
                }
                Button("Open outgoing links") {
                    linkedLinksMode = .outgoing
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
            "Delete \"\(file?.name ?? "this file")\"?",
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
        guard let path = workspace.diskPath(for: fileID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func openInDefaultApp() {
        guard let path = workspace.diskPath(for: fileID) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func exportPDF() {
        guard let file,
              let vaultURL = workspace.activeVaultURL else { return }
        let noteURL = vaultURL.appendingPathComponent(file.relativePath)
        guard FileManager.default.fileExists(atPath: noteURL.path) else {
            workspace.reportVaultError(title: "Export failed", message: "Could not locate the note on disk.")
            return
        }

        let printInfo = NSPrintInfo.shared
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.isEditable = false
        textView.string = "# \(file.name)\n\n\(file.noteContent)"
        textView.sizeToFit()

        let printOperation = NSPrintOperation(view: textView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.printInfo.jobDisposition = .save
        printOperation.run()
    }

    private func openInNewWindow() {
        workspace.reportVaultError(
            title: "New window",
            message: "Opening notes in a separate window isn't supported yet. Use a new tab instead."
        )
    }
    #else
    private func openInDefaultApp() {
        guard let path = workspace.diskPath(for: fileID) else { return }
        UIApplication.shared.open(URL(fileURLWithPath: path))
    }

    private func exportPDF() {
        guard let file else { return }
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let textRect = pageRect.insetBy(dx: 36, dy: 36)

        let content = NSMutableAttributedString()
        content.append(NSAttributedString(
            string: "\(file.name)\n\n",
            attributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor.black
            ]
        ))
        content.append(NSAttributedString(
            string: file.noteContent,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]
        ))

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            let framesetter = CTFramesetterCreateWithAttributedString(content)
            var location = 0
            repeat {
                context.beginPage()
                let path = CGPath(rect: textRect, transform: nil)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: location, length: 0),
                    path,
                    nil
                )

                let cgContext = context.cgContext
                cgContext.saveGState()
                cgContext.translateBy(x: 0, y: pageRect.height)
                cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cgContext)
                cgContext.restoreGState()

                let visible = CTFrameGetVisibleStringRange(frame)
                if visible.length == 0 { break }
                location = visible.location + visible.length
            } while location < content.length
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(file.name).pdf")
        do {
            try data.write(to: url, options: .atomic)
            IOSShareSheet.present(fileURL: url)
        } catch {
            workspace.reportVaultError(title: "Export failed", message: error.localizedDescription)
        }
    }

    private func openInNewWindow() {
        workspace.reportVaultError(
            title: "New window",
            message: "Opening notes in a separate window isn't supported on iPad yet."
        )
    }
    #endif
}

#if os(iOS)
import UIKit
import CoreText
#endif
