import SwiftUI

struct TimelapseWandButton: View {
    let isPlaying: Bool
    let isDisabled: Bool
    let onToggle: () -> Void
    var tooltipAnchor: ObsidianTooltipAnchor = .center

    @State private var isHovered = false

    private var tooltipText: String {
        isPlaying ? "Stop timelapse animation" : "Start timelapse animation"
    }

    #if os(iOS)
    private let iconSize: CGFloat = 17
    private let controlSize: CGFloat = 44
    private let cornerRadius: CGFloat = 8
    #else
    private let iconSize: CGFloat = 15
    private let controlSize: CGFloat = 36
    private let cornerRadius: CGFloat = 7
    #endif

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(Color(red: 0.38, green: 0.38, blue: 0.38))
                .frame(width: controlSize, height: controlSize)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        #if os(macOS)
        .onHover { hovering in
            DispatchQueue.main.async {
                isHovered = hovering
            }
        }
        #endif
        .background {
            Color.clear
                .frame(width: controlSize, height: controlSize)
                .obsidianTooltipBelow(
                    tooltipText,
                    isVisible: isHovered,
                    gap: controlSize + 4,
                    anchor: tooltipAnchor
                )
        }
        .accessibilityLabel(tooltipText)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
