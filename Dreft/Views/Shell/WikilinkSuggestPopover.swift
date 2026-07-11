import SwiftUI

struct WikilinkSuggestPopover: View {
    let results: [WorkspaceFileEntry]
    let selectedIndex: Int

    private let rowHeight: CGFloat = 30
    private let maxVisibleRows = 8

    private var listHeight: CGFloat {
        min(CGFloat(results.count) * rowHeight, CGFloat(maxVisibleRows) * rowHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.prefix(maxVisibleRows).enumerated()), id: \.element.id) { index, file in
                        Text(WikilinkEditorSupport.suggestionLabel(for: file))
                            .font(.system(size: 13))
                            .foregroundStyle(index == selectedIndex ? AppColors.textPrimary : AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: rowHeight)
                            .background(
                                index == selectedIndex
                                    ? AppColors.sidebarSelection
                                    : Color.clear
                            )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: listHeight)

            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 2) {
                footerHint("Type # to link heading")
                footerHint("Type ^ to link blocks")
                footerHint("Type | to change display text")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
        .background(AppColors.floatingChrome)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    private func footerHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(AppColors.textMuted)
    }
}
