import XCTest

/// UI tests run against fixture samplers (`--uitest-fixtures`), so every
/// asserted value is deterministic and unmistakable (FixtureProcA, Fixture HD,
/// FixtureNet) — real system state in the VM can't collide with them.
final class ActivityMonitorPlusUITests: XCTestCase {
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

    /// Identifier-first lookup with a label-text fallback, since macOS AX
    /// exposure of SwiftUI identifiers varies by element type.
    private func element(_ identifier: String, fallbackLabel: String? = nil) -> XCUIElement {
        let byIdentifier = app.descendants(matching: .any)[identifier].firstMatch
        if byIdentifier.exists { return byIdentifier }
        if let fallbackLabel {
            let byLabel = app.staticTexts[fallbackLabel].firstMatch
            if byLabel.exists { return byLabel }
        }
        return byIdentifier
    }

    private func openSidebarItem(_ name: String, fallbackLabel: String) {
        let text = element("sidebar.\(name)", fallbackLabel: fallbackLabel)
        XCTAssertTrue(text.waitForExistence(timeout: 10), "sidebar item \(name) not found")
        // Click the enclosing row cell when possible — a more reliable
        // selection target than the inner static text.
        let cell = app.cells.containing(.staticText, identifier: "sidebar.\(name)").firstMatch
        (cell.exists ? cell : text).click()
    }

    // MARK: Tests

    func testSidebarNavigation() {
        XCTAssertTrue(element("overview.root").waitForExistence(timeout: 10))

        openSidebarItem("processes", fallbackLabel: "Processes")
        XCTAssertTrue(element("processes.table").waitForExistence(timeout: 10))

        openSidebarItem("network", fallbackLabel: "Network")
        XCTAssertTrue(element("network.table").waitForExistence(timeout: 10))

        openSidebarItem("overview", fallbackLabel: "Overview")
        XCTAssertTrue(element("overview.root").waitForExistence(timeout: 10))
    }

    /// SwiftUI static texts outside tables expose their string via the AX
    /// *value* (empty label), so match on either.
    private func staticText(containing string: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", string, string)).firstMatch
    }

    private func text(of element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return value.isEmpty ? element.label : value
    }

    func testOverviewRendersFixtureData() {
        let total = element("overview.cpuTotalLabel")
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertEqual(text(of: total), "62%")

        XCTAssertTrue(element("overview.cpuDonut").exists)
        XCTAssertTrue(element("overview.cpuLegend.FixtureProcA", fallbackLabel: "FixtureProcA")
            .waitForExistence(timeout: 10))

        // Memory and network cards render fixture values.
        XCTAssertTrue(element("overview.memoryCard").exists)
        XCTAssertTrue(staticText(containing: "18 GB")
            .waitForExistence(timeout: 10), "memory used total missing")
        XCTAssertTrue(element("overview.networkCard").exists)
        XCTAssertTrue(staticText(containing: "1.3 MB/s").exists, "in-rate missing")

        // Activity-Monitor-style split row from the fixture host ticks.
        XCTAssertTrue(staticText(containing: "User 44%").waitForExistence(timeout: 10),
                      "cpu user/system/idle split missing")

        // Storage card shows the fixture volumes.
        XCTAssertTrue(element("overview.storage.Fixture HD", fallbackLabel: "Fixture HD")
            .waitForExistence(timeout: 10))
    }

    func testProcessTableSortsByCPU() {
        openSidebarItem("processes", fallbackLabel: "Processes")
        XCTAssertTrue(element("processes.table").waitForExistence(timeout: 10))

        let procA = app.staticTexts["FixtureProcA"].firstMatch
        let procF = app.staticTexts["FixtureProcF"].firstMatch
        XCTAssertTrue(procA.waitForExistence(timeout: 10))
        XCTAssertTrue(procF.exists)

        // Default sort is highest CPU first: A (30%) above F (1%).
        XCTAssertLessThan(procA.frame.minY, procF.frame.minY,
                          "expected FixtureProcA above FixtureProcF for Highest CPU")

        // Flip via the toolbar sort picker (stable AX path on macOS).
        let picker = element("processes.sortPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.click()
        let lowest = app.menuItems["Lowest CPU"].firstMatch
        XCTAssertTrue(lowest.waitForExistence(timeout: 5))
        lowest.click()

        XCTAssertTrue(procA.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(procA.frame.minY, procF.frame.minY,
                             "expected FixtureProcA below FixtureProcF for Lowest CPU")
    }

    func testMenuBarExtraExists() {
        // Icon-only status item (no percentage text, to avoid width jitter).
        let item = app.statusItems.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "menu bar status item missing")
    }

    func testProcessQuitRemovesRow() {
        openSidebarItem("processes", fallbackLabel: "Processes")
        XCTAssertTrue(element("processes.table").waitForExistence(timeout: 10))

        let procF = app.staticTexts["FixtureProcF"].firstMatch
        XCTAssertTrue(procF.waitForExistence(timeout: 10))
        procF.click() // select the row

        let quitButton = element("processes.quitButton")
        XCTAssertTrue(quitButton.waitForExistence(timeout: 5))
        quitButton.click()

        // Confirmation dialog: choose plain Quit (fixture controller marks the
        // pid killed; next fixture tick omits it).
        let confirmQuit = app.buttons["Quit"].firstMatch
        XCTAssertTrue(confirmQuit.waitForExistence(timeout: 5), "quit confirmation missing")
        confirmQuit.click()

        XCTAssertTrue(procF.waitForNonExistence(timeout: 10),
                      "FixtureProcF should disappear after quit")
        // The rest of the table is unaffected.
        XCTAssertTrue(app.staticTexts["FixtureProcA"].firstMatch.exists)
    }

    func testProcessInspectShowsDetails() {
        openSidebarItem("processes", fallbackLabel: "Processes")
        XCTAssertTrue(element("processes.table").waitForExistence(timeout: 10))

        let procA = app.staticTexts["FixtureProcA"].firstMatch
        XCTAssertTrue(procA.waitForExistence(timeout: 10))
        procA.click()

        let inspectButton = element("processes.inspectButton")
        XCTAssertTrue(inspectButton.waitForExistence(timeout: 5))
        inspectButton.click()

        // Anchor on concrete elements: bare layout containers don't surface
        // in the macOS AX tree, so the sheet is detected via its content.
        let path = element("inspect.path")
        XCTAssertTrue(path.waitForExistence(timeout: 5), "inspect sheet did not appear")
        XCTAssertTrue(text(of: path).contains("/Applications/FixtureProcA.app"),
                      "unexpected path text: \(text(of: path))")
        XCTAssertTrue(staticText(containing: "fixtureuser").exists, "user missing")

        let done = element("inspect.done", fallbackLabel: "Done")
        XCTAssertTrue(done.exists)
        done.click()
        XCTAssertTrue(path.waitForNonExistence(timeout: 5))
    }

    func testNetworkLogShowsFixtureEvents() {
        openSidebarItem("network", fallbackLabel: "Network")
        XCTAssertTrue(element("network.table").waitForExistence(timeout: 10))

        // The fixture script emits Opened at ~2s, Traffic at ~3s (cycle of 6s).
        let process = app.staticTexts["FixtureNet"].firstMatch
        XCTAssertTrue(process.waitForExistence(timeout: 15), "no FixtureNet event rows")

        XCTAssertTrue(app.staticTexts["93.184.216.34.443"].firstMatch.exists,
                      "remote address missing")
        XCTAssertTrue(app.staticTexts["Opened"].firstMatch.waitForExistence(timeout: 15),
                      "no Opened event")
        XCTAssertTrue(app.staticTexts["Traffic"].firstMatch.waitForExistence(timeout: 15),
                      "no Traffic event")
        // Traffic byte deltas from the fixture script.
        XCTAssertTrue(app.staticTexts["12.3 KB"].firstMatch.waitForExistence(timeout: 15),
                      "traffic bytes-in missing")
        XCTAssertTrue(app.staticTexts["4.5 KB"].firstMatch.exists,
                      "traffic bytes-out missing")

        // Pause and clear controls exist and respond.
        let pause = element("network.pauseButton")
        XCTAssertTrue(pause.exists)
        pause.click()
        let clear = element("network.clearButton")
        XCTAssertTrue(clear.exists)
    }

    func testStorageBreakdownOpensAndDrillsDown() {
        // Open the breakdown by clicking the fixture volume row on the Storage card.
        let row = element("overview.storage.Fixture HD", fallbackLabel: "Fixture HD")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        // The fixture scanner returns instantly; the sunburst legend lists the
        // deterministic top-level folders.
        let moviesRow = element("storage.breakdown.legend.Fixture Movies",
                                fallbackLabel: "Fixture Movies")
        XCTAssertTrue(moviesRow.waitForExistence(timeout: 15),
                      "storage breakdown sheet / legend did not appear")

        // Capture the working sunburst first so the shot survives any later
        // AX-flaky assertion.
        Thread.sleep(forTimeInterval: 1.0)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "04-storage-breakdown"
        shot.lifetime = .keepAlways
        add(shot)

        // Legend rows combine their children into the button, so they're found
        // by identifier, not by an inner static text.
        XCTAssertTrue(element("storage.breakdown.legend.Fixture Xcode",
                              fallbackLabel: "Fixture Xcode").exists, "Fixture Xcode legend missing")
        // The unattributed remainder against the fixture volume's used space.
        XCTAssertTrue(element("storage.breakdown.legend.System / hidden space").exists,
                      "hidden-space slice missing")
        // Center/header render the volume's used bytes (300 GB for Fixture HD).
        XCTAssertTrue(staticText(containing: "300 GB").waitForExistence(timeout: 5),
                      "used-bytes total missing")

        // Drill into a folder via its legend row; the breadcrumb and the new
        // ring's contents update.
        moviesRow.click()
        XCTAssertTrue(element("storage.breakdown.crumb.Fixture Movies",
                              fallbackLabel: "Fixture Movies").waitForExistence(timeout: 5),
                      "breadcrumb did not add the drilled folder")
        XCTAssertTrue(element("storage.breakdown.legend.BigMovie.mov",
                              fallbackLabel: "BigMovie.mov").waitForExistence(timeout: 5),
                      "drilled folder's contents not shown")

        // Close the sheet. "Done" is the sheet's default action; the button's
        // custom identifier isn't reliably exposed for a default-styled button,
        // so fall back to its title, then to the Return key.
        let drilled = element("storage.breakdown.legend.BigMovie.mov",
                              fallbackLabel: "BigMovie.mov")
        let doneById = app.buttons["storage.breakdown.done"].firstMatch
        let doneByTitle = app.buttons["Done"].firstMatch
        if doneById.exists { doneById.click() }
        else if doneByTitle.exists { doneByTitle.click() }
        else { app.typeKey("\r", modifierFlags: []) }
        XCTAssertTrue(drilled.waitForNonExistence(timeout: 5), "breakdown sheet did not dismiss")
    }

    /// Drilling into a many-file folder fills the legend past the visible area,
    /// so the overlay scrollbar appears. The fix reserves a trailing gutter so
    /// the bar floats beside the rows rather than over their chevron/size —
    /// this captures the regression shot for the long-list overlap.
    func testStorageBreakdownLongListScrollbar() {
        let row = element("overview.storage.Fixture HD", fallbackLabel: "Fixture HD")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        // Drill into the many-file fixture folder.
        let music = element("storage.breakdown.legend.Fixture Music",
                            fallbackLabel: "Fixture Music")
        XCTAssertTrue(music.waitForExistence(timeout: 15),
                      "storage breakdown legend did not appear")
        music.click()

        // 20 itemized tracks + a "smaller items" fold — more rows than fit, so
        // the legend scrolls.
        let firstTrack = element("storage.breakdown.legend.FixtureTrack-01.mp3",
                                 fallbackLabel: "FixtureTrack-01.mp3")
        XCTAssertTrue(firstTrack.waitForExistence(timeout: 5),
                      "drilled folder's tracks not shown")

        // Scroll so the overlay scrollbar is drawn, then shoot right away —
        // overlay scrollers fade ~1s after the gesture ends. Two shots in quick
        // succession to improve the odds of catching the bar mid-fade.
        firstTrack.swipeUp()
        for name in ["05-storage-long-list-a", "05-storage-long-list-b"] {
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
