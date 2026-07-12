import SwiftUI

@main
struct ActivityMonitorPlusApp: App {
    @State private var model: AppModel
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    init() {
        let useFixtures = CommandLine.arguments.contains("--uitest-fixtures")
        _model = State(initialValue: AppModel(
            samplers: useFixtures ? .fixtures() : .live()))
    }

    private var colorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            AppearanceSettingsView()
                .preferredColorScheme(colorScheme)
        }

        MenuBarExtra {
            MenuBarContentView()
                .environment(model)
                .preferredColorScheme(colorScheme)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}
