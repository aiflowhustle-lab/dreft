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

    /// Compact row — matches the card icon toolbar width, not a full panel.
    private var colorRowLayoutWidth: CGFloat { 184 }
    private var swatchSize: CGFloat { 14 }
    private var swatchSlotWidth: CGFloat { 22 }

    private var isCustomPresetColor: Bool {
        guard let hex = activeColorHex, !hex.isEmpty else { return false }
        return cardColors.contains { $0.hex.uppercased() == hex.uppercased() }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(cardColors, id: \.name) { entry in
                ColorSwatchButton(
                    hex: entry.hex,
                    name: entry.name,
                    swatchSize: swatchSize,
                    slotWidth: swatchSlotWidth,
                    isActive: (activeColorHex ?? "").uppercased() == entry.hex.uppercased(),
                    action: { onSetColor(entry.hex) }
                )
            }
            customColorSwatch
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .frame(width: colorRowLayoutWidth)
        .background(AppColors.canvasBackground.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.floatingChromeBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.floatingChromeShadow, radius: 10, y: 3)
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
                .frame(width: swatchSize, height: swatchSize)
                .overlay {
                    if activeColorHex != nil, !isCustomPresetColor {
                        Circle()
                            .stroke(AppColors.selectionStroke, lineWidth: 1.5)
                            .padding(-2)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: swatchSlotWidth, height: swatchSize + 4)
        .contentShape(Rectangle())
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
        let swatchSize: CGFloat
        let slotWidth: CGFloat
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
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay(
                        Circle()
                            .stroke(
                                swatchColor.opacity(isActive ? 1 : (hovered ? 0.5 : 0)),
                                lineWidth: 1.5
                            )
                            .padding(-2)
                    )
                    .scaleEffect(hovered && !isActive ? 1.08 : 1)
                    .animation(.easeOut(duration: 0.12), value: hovered)
            }
            .buttonStyle(.plain)
            .frame(width: slotWidth, height: swatchSize + 4)
            .contentShape(Rectangle())
            .help(name)
            .onHover { hovered = $0 }
        }
    }
}
