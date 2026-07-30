import SwiftUI

struct WikilinkSuggestPopover: View {
    let results: [WorkspaceFileEntry]
    @Binding var selectedIndex: Int
    var onSelect: (WorkspaceFileEntry) -> Void

    static let preferredWidth: CGFloat = 300
    static let rowHeight: CGFloat = 28
    static let footerHeight: CGFloat = 68

    private let rowHeight: CGFloat = Self.rowHeight
    private let maxVisibleRows = 8
    private let footerHeight: CGFloat = Self.footerHeight

    static func estimatedHeight(resultCount: Int) -> CGFloat {
        let rows = min(resultCount, 8)
        let listHeight = CGFloat(rows) * 28 + 8
        return listHeight + 68
    }

    private var popoverWidth: CGFloat { Self.preferredWidth }

    private var listHeight: CGFloat {
        min(CGFloat(results.count) * rowHeight, CGFloat(maxVisibleRows) * rowHeight) + 8
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.prefix(maxVisibleRows).enumerated()), id: \.element.id) { index, file in
                        WikilinkSuggestRow(
                            label: WikilinkEditorSupport.suggestionLabel(for: file),
                            isSelected: index == selectedIndex,
                            onHover: {
                                #if os(macOS)
                                if $0 { selectedIndex = index }
                                #endif
                            },
                            onSelect: { onSelect(file) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .frame(height: listHeight)

            footerHints
        }
        .frame(width: popoverWidth)
        .background(AppColors.floatingChrome)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: AppColors.floatingChromeShadow, radius: 12, x: 0, y: 4)
    }

    private var footerHints: some View {
        VStack(alignment: .leading, spacing: 3) {
            footerHint("Type # to link heading")
            footerHint("Type ^ to link blocks")
            footerHint("Type | to change display text")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
    }

    private func footerHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(AppColors.textMuted)
    }
}

private struct WikilinkSuggestRow: View {
    let label: String
    let isSelected: Bool
    var onHover: (Bool) -> Void
    var onSelect: () -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    var body: some View {
        Button(action: onSelect) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(isHighlighted ? Color.primary.opacity(0.07) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        #endif
    }
}
