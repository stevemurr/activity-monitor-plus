import SwiftUI

@main
struct ActivityMonitorPlusApp: App {
    @State private var model: AppModel

    init() {
        let useFixtures = CommandLine.arguments.contains("--uitest-fixtures")
        _model = State(initialValue: AppModel(
            samplers: useFixtures ? .fixtures() : .live()))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra {
            MenuBarContentView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
