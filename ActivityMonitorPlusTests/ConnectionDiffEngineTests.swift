import XCTest
@testable import ActivityMonitorPlus

final class ConnectionDiffEngineTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(local: String = "10.0.0.1.5000",
                          remote: String = "93.184.216.34.443",
                          pid: Int32 = 4242,
                          name: String = "TestProc",
                          rx: UInt64 = 0,
                          tx: UInt64 = 0) -> ConnectionSnapshot {
        ConnectionSnapshot(
            key: ConnectionKey(proto: .tcp, local: local, remote: remote, pid: pid),
            processName: name, state: "ESTABLISHED", rxBytes: rx, txBytes: tx)
    }

    func testFirstSnapshotIsBaselineWithNoEvents() {
        var engine = ConnectionDiffEngine()
        let events = engine.ingest([snapshot(rx: 100, tx: 50)], at: date)
        XCTAssertTrue(events.isEmpty)
    }

    func testNewConnectionEmitsOpenedAndInitialTraffic() {
        var engine = ConnectionDiffEngine()
        _ = engine.ingest([], at: date)
        let events = engine.ingest([snapshot(rx: 300, tx: 120)], at: date)
        XCTAssertEqual(events.map(\.kind).sorted { $0.rawValue < $1.rawValue },
                       [.opened, .traffic])
        let traffic = events.first { $0.kind == .traffic }!
        XCTAssertEqual(traffic.bytesIn, 300)
        XCTAssertEqual(traffic.bytesOut, 120)
    }

    func testByteGrowthEmitsTrafficDelta() {
        var engine = ConnectionDiffEngine()
        _ = engine.ingest([snapshot(rx: 1000, tx: 500)], at: date)
        let events = engine.ingest([snapshot(rx: 1500, tx: 700)], at: date)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .traffic)
        XCTAssertEqual(events[0].bytesIn, 500)
        XCTAssertEqual(events[0].bytesOut, 200)
    }

    func testUnchangedConnectionEmitsNothing() {
        var engine = ConnectionDiffEngine()
        _ = engine.ingest([snapshot(rx: 1000, tx: 500)], at: date)
        XCTAssertTrue(engine.ingest([snapshot(rx: 1000, tx: 500)], at: date).isEmpty)
    }

    func testVanishedConnectionEmitsClosedWithFinalBytes() {
        var engine = ConnectionDiffEngine()
        _ = engine.ingest([snapshot(rx: 1000, tx: 500)], at: date)
        let events = engine.ingest([], at: date)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .closed)
        XCTAssertEqual(events[0].bytesIn, 1000)
        XCTAssertEqual(events[0].bytesOut, 500)
    }

    func testCounterRegressionEmitsClosedThenOpened() {
        var engine = ConnectionDiffEngine()
        _ = engine.ingest([snapshot(rx: 9000, tx: 4000)], at: date)
        let events = engine.ingest([snapshot(rx: 10, tx: 5)], at: date)
        let kinds = events.map(\.kind)
        XCTAssertTrue(kinds.contains(.closed))
        XCTAssertTrue(kinds.contains(.opened))
        let closed = events.first { $0.kind == .closed }!
        XCTAssertEqual(closed.bytesIn, 9000)
    }

    func testSameTupleDifferentPidsAreDistinctConnections() {
        var engine = ConnectionDiffEngine()
        let a = snapshot(pid: 100, name: "ProcA", rx: 10, tx: 10)
        let b = snapshot(pid: 200, name: "ProcB", rx: 20, tx: 20)
        _ = engine.ingest([a, b], at: date)
        // Only ProcA's socket goes away.
        let events = engine.ingest([b], at: date)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .closed)
        XCTAssertEqual(events[0].pid, 100)
    }

    func testTrafficEventsAreCappedKeepingLargest() {
        var engine = ConnectionDiffEngine()
        let base = (0..<150).map { i in
            snapshot(local: "10.0.0.1.\(6000 + i)", rx: 0, tx: 0)
        }
        _ = engine.ingest(base, at: date)
        let grown = (0..<150).map { i in
            snapshot(local: "10.0.0.1.\(6000 + i)", rx: UInt64(i + 1), tx: 0)
        }
        let events = engine.ingest(grown, at: date)
        let traffic = events.filter { $0.kind == .traffic }
        XCTAssertEqual(traffic.count, ConnectionDiffEngine.maxTrafficEventsPerTick)
        // The largest mover survived the cap; the smallest did not.
        XCTAssertTrue(traffic.contains { $0.bytesIn == 150 })
        XCTAssertFalse(traffic.contains { $0.bytesIn == 1 })
    }
}
