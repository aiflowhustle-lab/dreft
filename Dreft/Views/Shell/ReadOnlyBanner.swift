import SwiftUI

struct ReadOnlyBanner: View {
    var onUpgrade: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your subscription has ended.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Your writing is safe — you can read and export everything. Subscribe to start writing again.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Upgrade") {
                onUpgrade()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppColors.sidebarSelection)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.toolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(height: 1)
        }
    }
}
