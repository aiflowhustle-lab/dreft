import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DreftHelpView: View {
    @Bindable var workspace: WorkspaceStore
    @Environment(\.openURL) private var openURL

    private static let documentationURL = URL(string: "https://dreft.app/help")!

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
                DreftGemLogo()
                    .frame(width: 52, height: 52)
                    .padding(.top, 28)

                Text("Dreft")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 14)

                Text("Version \(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
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
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.035))
                )
                .padding(.horizontal, 28)

                Spacer()
            }
            #if os(iOS)
            .frame(maxWidth: 420, maxHeight: 360)
            .padding(.horizontal, 20)
            #else
            .frame(width: 420, height: 360)
            #endif
            .background(Color(red: 0.125, green: 0.12, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 40, y: 18)
        }
    }

    private func closeHelp() {
        workspace.isHelpOpen = false
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
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isPrimary ? AppColors.selectionStroke : Color.white.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(isPrimary ? 0 : 0.12), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
