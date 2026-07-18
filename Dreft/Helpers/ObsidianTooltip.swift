import SwiftUI

enum ObsidianTooltipAnchor {
    /// Caret centered on the anchor view (graph view).
    case center
    /// Caret aligned to the anchor's leading edge — tooltip grows right (canvas beside sidebar).
    case leading(caretCenterX: CGFloat = 15)
}

/// Obsidian-style hover label: black box with a caret pointing up toward the anchor.
struct ObsidianTooltipLabel: View {
    let text: String
    var anchor: ObsidianTooltipAnchor = .center

    var body: some View {
        VStack(alignment: vStackAlignment, spacing: 0) {
            caretRow
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

    private var vStackAlignment: HorizontalAlignment {
        switch anchor {
        case .center: return .center
        case .leading: return .leading
        }
    }

    @ViewBuilder
    private var caretRow: some View {
        switch anchor {
        case .center:
            ObsidianTooltipCaret()
                .fill(Color.black)
                .frame(width: 10, height: 5)
        case .leading(let caretCenterX):
            ObsidianTooltipCaret()
                .fill(Color.black)
                .frame(width: 10, height: 5)
                .padding(.leading, max(0, caretCenterX - 5))
        }
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
    /// Shows an Obsidian-style tooltip below the view.
    func obsidianTooltipBelow(
        _ text: String,
        isVisible: Bool,
        gap: CGFloat = 4,
        anchor: ObsidianTooltipAnchor = .center
    ) -> some View {
        overlay(alignment: overlayAlignment(for: anchor)) {
            if isVisible {
                ObsidianTooltipLabel(text: text, anchor: anchor)
                    .offset(y: gap)
                    .zIndex(200)
                    .transition(.opacity)
            }
        }
    }

    private func overlayAlignment(for anchor: ObsidianTooltipAnchor) -> Alignment {
        switch anchor {
        case .center:
            return .top
        case .leading:
            return .topLeading
        }
    }
}
