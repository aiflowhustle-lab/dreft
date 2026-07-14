import SwiftUI

struct AppearanceSettingsSection: View {
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.dark.rawValue

    /// Applies the theme in the setter so the new palette is installed before
    /// any view re-renders from the storage change.
    private var appearanceSelection: Binding<String> {
        Binding(
            get: { appearanceModeRaw },
            set: { newValue in
                let mode = AppearanceMode(rawValue: newValue) ?? .dark
                AppColors.setTheme(mode.theme)
                appearanceModeRaw = newValue
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Picker("Appearance", selection: appearanceSelection) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text("Dark matches the default canvas. Light uses a white canvas and light sidebar.")
                .font(.system(size: 11.5))
                .foregroundStyle(AppColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
