import XCTest

/// Captures high-resolution window screenshots of each view (with deterministic
/// fixture data) as test attachments, for the README. Runs in the VM like the
/// rest of the UI tests.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest-fixtures"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        app = nil
    }

    private func capture(_ name: String) {
        // Let layout/animation settle so the shot is clean.
        Thread.sleep(forTimeInterval: 1.0)
        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSidebar(_ identifier: String, fallback: String) {
        let text = app.descendants(matching: .any)["sidebar.\(identifier)"].firstMatch
        let target = text.exists ? text : app.staticTexts[fallback].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let cell = app.cells.containing(.staticText, identifier: "sidebar.\(identifier)").firstMatch
        (cell.exists ? cell : target).click()
    }

    func testCaptureScreenshots() {
        XCTAssertTrue(app.descendants(matching: .any)["overview.root"]
            .waitForExistence(timeout: 10))
        capture("01-overview")

        openSidebar("processes", fallback: "Processes")
        XCTAssertTrue(app.descendants(matching: .any)["processes.table"]
            .waitForExistence(timeout: 10))
        capture("02-processes")

        openSidebar("network", fallback: "Network")
        XCTAssertTrue(app.descendants(matching: .any)["network.table"]
            .waitForExistence(timeout: 10))
        // Give the fixture connection events a couple of ticks to appear.
        Thread.sleep(forTimeInterval: 4.0)
        capture("03-network")
    }
}
