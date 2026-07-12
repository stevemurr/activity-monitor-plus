import SwiftUI

/// User's appearance preference. `.system` follows the OS light/dark setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil means "follow the system", which is SwiftUI's default behavior.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue })
    }

    var body: some View {
        Form {
            Picker("Appearance", selection: appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearancePicker")
            Text("“System” follows your macOS Appearance setting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
    }
}
