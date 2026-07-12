import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum CanvasExportViewport: String, CaseIterable, Identifiable {
    case fullCanvas
    case viewportOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullCanvas: "Full canvas"
        case .viewportOnly: "Viewport only"
        }
    }
}

struct CanvasImageExportSheet: View {
    @Bindable var workspace: WorkspaceStore
    @Bindable var canvasStore: CanvasStore
    let fileID: String

    @Environment(\.dismiss) private var dismiss
    @State private var viewport: CanvasExportViewport = .fullCanvas
    @State private var exportZoom: CGFloat = 1
    @State private var showLogo = true
    @State private var privacyMode = false
    @State private var isExporting = false

    private var fileName: String {
        workspace.files.first(where: { $0.id == fileID })?.name ?? "Canvas"
    }

    private var snapshot: CanvasDocumentSnapshot {
        canvasStore.documentSnapshot
    }

    private var exportBounds: CGRect {
        switch viewport {
        case .fullCanvas:
            return CanvasExportView.fullCanvasBounds(for: snapshot)
        case .viewportOnly:
            guard canvasStore.viewportSize.width > 0,
                  canvasStore.viewportSize.height > 0 else {
                return CanvasExportView.fullCanvasBounds(for: snapshot)
            }
            let transform = canvasStore.transform
            let zoom = max(transform.zoom, 0.001)
            return CGRect(
                x: -transform.x / zoom,
                y: -transform.y / zoom,
                width: canvasStore.viewportSize.width / zoom,
                height: canvasStore.viewportSize.height / zoom
            )
        }
    }

    private var estimatedSize: CGSize {
        CanvasExportView.outputSize(for: exportBounds, requestedScale: exportZoom)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Text("Export “\(fileName)” as a PNG file with the settings below.")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            Divider().opacity(0.35)

            exportRow(
                title: "Viewport",
                subtitle: "Choose to render the entire canvas or just the current visible viewport."
            ) {
                Picker("", selection: $viewport) {
                    ForEach(CanvasExportViewport.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            Divider().opacity(0.25)

            exportRow(
                title: "Zoom",
                subtitle: "Estimated image dimensions: \(dimensionText)"
            ) {
                Slider(value: $exportZoom, in: 0.25...4)
                    .frame(width: 125)
            }

            Divider().opacity(0.25)

            exportRow(
                title: "Show logo",
                subtitle: "Adds a Dreft logo to the bottom left."
            ) {
                Toggle("", isOn: $showLogo)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AppColors.selectionStroke)
            }

            Divider().opacity(0.25)

            exportRow(
                title: "Privacy mode",
                subtitle: "Obscures text on the exported canvas."
            ) {
                Toggle("", isOn: $privacyMode)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AppColors.selectionStroke)
            }

            Divider().opacity(0.25)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)

                Button {
                    save()
                } label: {
                    Group {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(minWidth: 42)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppColors.selectionStroke)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isExporting || snapshot.cards.isEmpty)
                .opacity(snapshot.cards.isEmpty ? 0.45 : 1)
            }
            .padding(16)
        }
        .frame(width: 440)
        .background(Color(hex: 0x202020))
        .foregroundStyle(AppColors.textPrimary)
    }

    private var header: some View {
        HStack {
            Text("Export as image")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var dimensionText: String {
        let width = Int(estimatedSize.width)
        let height = Int(estimatedSize.height)
        return "\(width.formatted()) × \(height.formatted())px"
    }

    private func exportRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func save() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(fileName).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        let renderer = ImageRenderer(
            content: CanvasExportView(
                snapshot: snapshot,
                vaultURL: workspace.activeVaultURL,
                cropBounds: exportBounds,
                requestedScale: exportZoom,
                showLogo: showLogo,
                privacyMode: privacyMode
            )
        )
        renderer.scale = 1

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            isExporting = false
            workspace.reportVaultError(
                title: "Export failed",
                message: "Dreft could not render this canvas as an image."
            )
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            isExporting = false
            dismiss()
        } catch {
            isExporting = false
            workspace.reportVaultError(title: "Export failed", message: error.localizedDescription)
        }
        #else
        workspace.reportVaultError(
            title: "Export as image",
            message: "Canvas image export is currently available on macOS."
        )
        #endif
    }
}
