import SwiftUI

/// Obsidian-style inline color picker row for canvas cards and connection lines.
struct CanvasCardColorSwatchRow: View {
    let activeColorHex: String?
    let frameWidth: CGFloat
    let zoom: CGFloat
    let cardColors: [(name: String, hex: String)]
    @Binding var showCustomColorPicker: Bool
    var onSetColor: (String) -> Void

    private var activeColor: Color? {
        guard let hex = activeColorHex else { return nil }
        return Color(hexString: hex)
    }

    private var toolbarWorldScale: CGFloat {
        CanvasFloatingToolbarChrome.counterScale(for: zoom)
    }

    private var colorRowLayoutWidth: CGFloat { 280 }

    private var isCustomPresetColor: Bool {
        guard let hex = activeColorHex, !hex.isEmpty else { return false }
        return cardColors.contains { $0.hex.uppercased() == hex.uppercased() }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(cardColors, id: \.name) { entry in
                ColorSwatchButton(
                    hex: entry.hex,
                    name: entry.name,
                    isActive: (activeColorHex ?? "").uppercased() == entry.hex.uppercased(),
                    action: { onSetColor(entry.hex) }
                )
                .frame(maxWidth: .infinity)
            }
            customColorSwatch
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: colorRowLayoutWidth)
        .background(AppColors.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 4)
    }

    private var customColorSwatch: some View {
        Button {
            showCustomColorPicker = true
        } label: {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                        center: .center
                    )
                )
                .frame(width: 18, height: 18)
                .overlay {
                    if activeColorHex != nil, !isCustomPresetColor {
                        Circle()
                            .stroke(AppColors.selectionStroke, lineWidth: 1.5)
                            .padding(-3)
                    }
                }
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .frame(maxWidth: .infinity, minHeight: CanvasPencilInteraction.colorSwatchHitSize)
        .contentShape(Rectangle())
        #endif
        .help("Custom color")
        .popover(isPresented: $showCustomColorPicker, arrowEdge: .bottom) {
            AdvancedColorPickerPopover(
                color: Binding(
                    get: { activeColor ?? AppColors.selectionStroke },
                    set: { onSetColor($0.canvasHexString) }
                )
            )
        }
    }

    private struct ColorSwatchButton: View {
        let hex: String
        let name: String
        let isActive: Bool
        let action: () -> Void
        @State private var hovered = false

        private var swatchColor: Color {
            Color(hexString: hex) ?? Color(white: 0.45)
        }

        var body: some View {
            Button(action: action) {
                Circle()
                    .fill(swatchColor)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(
                                swatchColor.opacity(isActive ? 1 : (hovered ? 0.5 : 0)),
                                lineWidth: 1.5
                            )
                            .padding(-3)
                    )
                    .scaleEffect(hovered && !isActive ? 1.08 : 1)
                    .animation(.easeOut(duration: 0.12), value: hovered)
            }
            .buttonStyle(.plain)
            #if os(iOS)
            .frame(maxWidth: .infinity, minHeight: CanvasPencilInteraction.colorSwatchHitSize)
            .contentShape(Rectangle())
            #endif
            .help(name)
            .onHover { hovered = $0 }
        }
    }
}
