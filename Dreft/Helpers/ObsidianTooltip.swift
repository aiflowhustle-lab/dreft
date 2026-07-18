import SwiftUI

/// Obsidian-style hover label: black box with a caret pointing up toward the anchor.
struct ObsidianTooltipLabel: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            ObsidianTooltipCaret()
                .fill(Color.black)
                .frame(width: 10, height: 5)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black)
                )
        }
        .fixedSize()
        .allowsHitTesting(false)
    }
}

private struct ObsidianTooltipCaret: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Shows an Obsidian-style tooltip centered under the view.
    func obsidianTooltipBelow(_ text: String, isVisible: Bool, gap: CGFloat = 4) -> some View {
        overlay(alignment: .top) {
            if isVisible {
                ObsidianTooltipLabel(text: text)
                    .offset(y: gap)
                    .zIndex(200)
                    .transition(.opacity)
            }
        }
    }
}
