import SwiftUI

@main
struct ActivityMonitorPlusApp: App {
    @NSApplicationDelegateAdaptor(ActivityMonitorAppDelegate.self)
    private var appDelegate
    @State private var model: AppModel
    @State private var mcpController: ActivityMonitorMCPController?
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    init() {
        let useFixtures = CommandLine.arguments.contains("--uitest-fixtures")
        let model = AppModel(samplers: useFixtures ? .fixtures() : .live())
        let isAutomatedRun = useFixtures || ActivityMonitorAppDelegate.isUnitTest
        let defaults: UserDefaults
        if isAutomatedRun {
            let suite = "com.stevemurr.activity-monitor-plus.tests.localmcp.\(ProcessInfo.processInfo.processIdentifier)"
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(false, forKey: ActivityMonitorMCPController.enabledDefaultsKey)
        } else {
            defaults = .standard
        }
        let controller: ActivityMonitorMCPController?
        do {
            let runtime = try ActivityMonitorMCPRuntimeFactory.makeLive(
                data: AppModelMCPBridge(model: model)
            )
            controller = ActivityMonitorMCPController(
                runtime: runtime,
                defaults: defaults
            )
        } catch {
            // The monitoring UI remains useful if optional Local MCP grant
            // storage cannot initialize; Settings reports it unavailable.
            controller = nil
        }
        _model = State(initialValue: model)
        _mcpController = State(initialValue: controller)
        appDelegate.configure(
            model: model,
            mcpController: controller,
            shouldStartMCP: !isAutomatedRun
        )
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
        .defaultSize(width: 1280, height: 820)

        Settings {
            ActivityMonitorSettingsView(mcpController: mcpController)
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
