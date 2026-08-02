import AppKit
import Foundation

@MainActor
final class ActivityMonitorAppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var mcpController: ActivityMonitorMCPController?
    private var shouldStartMCP = false
    private var didFinishLaunching = false
    private var terminationInProgress = false

    static var isUnitTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func configure(
        model: AppModel,
        mcpController: ActivityMonitorMCPController?,
        shouldStartMCP: Bool
    ) {
        self.model = model
        self.mcpController = mcpController
        self.shouldStartMCP = shouldStartMCP
        if didFinishLaunching, shouldStartMCP {
            mcpController?.startAfterMonitoringReady()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        guard !Self.isUnitTest, shouldStartMCP else { return }
        mcpController?.startAfterMonitoringReady()
    }

    /// Stop the authenticated listener before sampling state disappears, and
    /// keep macOS waiting until no in-flight consumer call can outlive the app.
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard model != nil || mcpController != nil else { return .terminateNow }
        guard !terminationInProgress else { return .terminateLater }
        terminationInProgress = true
        Task { @MainActor in
            if let mcpController {
                await mcpController.shutdown()
            }
            if let model {
                await model.shutdown()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
