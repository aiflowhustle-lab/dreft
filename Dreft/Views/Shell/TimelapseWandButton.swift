import SwiftUI

struct TimelapseWandButton: View {
    let isPlaying: Bool
    let isDisabled: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    private var tooltipText: String {
        isPlaying ? "Stop timelapse animation" : "Start timelapse animation"
    }

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(red: 0.38, green: 0.38, blue: 0.38))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                .frame(width: 30, height: 30)
                .obsidianTooltipBelow(tooltipText, isVisible: isHovered, gap: 34)
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
