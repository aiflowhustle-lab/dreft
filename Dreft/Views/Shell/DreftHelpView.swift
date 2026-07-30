import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DreftHelpView: View {
    @Bindable var workspace: WorkspaceStore
    @Environment(\.openURL) private var openURL

    private static let documentationURL = URL(string: "https://lavish-birthday-3cc.notion.site/Dreft-Help-Support-39e2796a24538094b200c799f7ddf41d")!

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

            ScrollView {
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
                            openURL(StoreConstants.privacyPolicyURL)
                        }

                        Divider()
                            .background(AppColors.borderSubtle)
                            .padding(.leading, 48)

                        helpActionRow(
                            icon: "doc.text",
                            title: "Terms of service",
                            subtitle: "Subscription terms, billing, and usage.",
                            buttonTitle: "View",
                            isPrimary: false
                        ) {
                            openURL(StoreConstants.termsOfUseURL)
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
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.visible)
            #if os(iOS)
            .frame(maxWidth: 420, maxHeight: 420)
            .padding(.horizontal, 20)
            #else
            .frame(width: 420, height: 440)
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isPrimary ? .white : AppColors.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isPrimary ? AppColors.selectionStroke : AppColors.sidebarSelection)
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
