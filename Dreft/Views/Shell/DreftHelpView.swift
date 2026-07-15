import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DreftHelpView: View {
    @Bindable var workspace: WorkspaceStore
    @Environment(\.openURL) private var openURL

    private static let documentationURL = URL(string: "https://lavish-birthday-3cc.notion.site/Dreft-Help-Support-39e2796a24538094b200c799f7ddf41d")!
    private static let privacyPolicyURL = URL(string: "https://lavish-birthday-3cc.notion.site/Dreft-Privacy-Policy-39e2796a245380869bb7f48509695d5e")!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    closeHelp()
                }

            VStack(spacing: 0) {
                DreftAppMark(cornerRadius: 12)
                    .frame(width: 52, height: 52)
                    .padding(.top, 28)

                Text("Dreft")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.top, 14)

                Text("Version \(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 2)

                Spacer().frame(height: 24)

                VStack(spacing: 0) {
                    helpActionRow(
                        icon: "book",
                        title: "Official help site",
                        subtitle: "Read the official help documentation for Dreft.",
                        buttonTitle: "Visit",
                        isPrimary: true
                    ) {
                        openURL(Self.documentationURL)
                    }

                    Divider()
                        .background(AppColors.borderSubtle)
                        .padding(.leading, 48)

                    helpActionRow(
                        icon: "hand.raised",
                        title: "Privacy policy",
                        subtitle: "How Dreft handles your data on your device.",
                        buttonTitle: "View",
                        isPrimary: false
                    ) {
                        openURL(Self.privacyPolicyURL)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.sidebarSelection)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.borderSubtle, lineWidth: 1)
                )
                .padding(.horizontal, 28)

                Spacer()
            }
            #if os(iOS)
            .frame(maxWidth: 420, maxHeight: 360)
            .padding(.horizontal, 20)
            #else
            .frame(width: 420, height: 400)
            #endif
            .background(AppColors.overlayPanel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .shadow(color: AppColors.floatingChromeShadow, radius: 40, y: 18)
            .onTapGesture { }
        }
    }

    private func closeHelp() {
        withAnimation(.easeOut(duration: 0.15)) {
            workspace.isHelpOpen = false
        }
    }

    private func helpActionRow(
        icon: String,
        title: String,
        subtitle: String,
        buttonTitle: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.textPrimary.opacity(0.85))
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isPrimary ? Color.white : AppColors.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isPrimary ? AppColors.selectionStroke : AppColors.pillButtonFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        isPrimary ? Color.clear : AppColors.border,
                                        lineWidth: 1
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
