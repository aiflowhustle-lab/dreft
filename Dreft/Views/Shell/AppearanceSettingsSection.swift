import SwiftUI

struct AppearanceSettingsSection: View {
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.dark.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Picker("Appearance", selection: $appearanceModeRaw) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearanceModeRaw) { _, newValue in
                let mode = AppearanceMode(rawValue: newValue) ?? .dark
                AppColors.setTheme(mode.theme)
            }

            Text("Dark matches the default canvas. Light uses a white canvas and light sidebar.")
                .font(.system(size: 11.5))
                .foregroundStyle(AppColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
