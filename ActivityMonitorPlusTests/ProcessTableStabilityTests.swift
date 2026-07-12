import XCTest
@testable import ActivityMonitorPlus

final class ProcessSmootherTests: XCTestCase {
    private func sample(pid: Int32, cpu: Double?) -> ProcessSample {
        ProcessSample(pid: pid, name: "P\(pid)", cpuFraction: cpu, residentBytes: nil)
    }

    func testFirstSampleTakenAsIs() {
        var smoother = ProcessSmoother(alpha: 0.35)
        let out = smoother.smooth([sample(pid: 1, cpu: 0.5)])
        XCTAssertEqual(out[0].cpuFraction, 0.5)
    }

    func testSecondSampleIsBlended() {
        var smoother = ProcessSmoother(alpha: 0.35)
        _ = smoother.smooth([sample(pid: 1, cpu: 0.5)])
        let out = smoother.smooth([sample(pid: 1, cpu: 1.0)])
        // 0.35 * 1.0 + 0.65 * 0.5
        XCTAssertEqual(out[0].cpuFraction!, 0.675, accuracy: 1e-9)
    }

    func testSmoothingDampsOscillation() {
        var smoother = ProcessSmoother(alpha: 0.35)
        _ = smoother.smooth([sample(pid: 1, cpu: 0.10)])
        var values: [Double] = []
        for raw in [0.30, 0.10, 0.30, 0.10] {
            values.append(smoother.smooth([sample(pid: 1, cpu: raw)])[0].cpuFraction!)
        }
        // Smoothed swing is well inside the raw 0.10...0.30 swing.
        let swing = values.max()! - values.min()!
        XCTAssertLessThan(swing, 0.10)
    }

    func testNilStaysNil() {
        var smoother = ProcessSmoother()
        let out = smoother.smooth([sample(pid: 1, cpu: nil)])
        XCTAssertNil(out[0].cpuFraction)
    }

    func testDeadPidStateIsPurged() {
        var smoother = ProcessSmoother(alpha: 0.35)
        _ = smoother.smooth([sample(pid: 1, cpu: 0.9)])
        _ = smoother.smooth([])  // pid 1 gone; its EMA state must not survive
        let out = smoother.smooth([sample(pid: 1, cpu: 0.1)])
        XCTAssertEqual(out[0].cpuFraction, 0.1)
    }
}

final class StableRankerTests: XCTestCase {
    private let cpuDescending = [KeyPathComparator(\ProcessRow.cpuSortKey,
                                                   order: SortOrder.reverse)]
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func row(_ pid: Int32, cpu: Double) -> ProcessRow {
        ProcessRow(pid: pid, name: "P\(pid)", cpuFraction: cpu, residentBytes: nil)
    }

    func testInitialCallSortsAndFreezesOrder() {
        var ranker = StableRanker(interval: 3)
        let out = ranker.orderedRows([row(1, cpu: 0.1), row(2, cpu: 0.9)],
                                     sortedBy: cpuDescending, now: t0)
        XCTAssertEqual(out.map(\.pid), [2, 1])
    }

    func testOrderHeldWhileValuesFlipWithinInterval() {
        var ranker = StableRanker(interval: 3)
        _ = ranker.orderedRows([row(1, cpu: 0.1), row(2, cpu: 0.9)],
                               sortedBy: cpuDescending, now: t0)
        // One second later the values have flipped — order must not change.
        let out = ranker.orderedRows([row(1, cpu: 0.9), row(2, cpu: 0.1)],
                                     sortedBy: cpuDescending, now: t0.addingTimeInterval(1))
        XCTAssertEqual(out.map(\.pid), [2, 1])
        // Values still update in place.
        XCTAssertEqual(out[0].cpuFraction, 0.1)
    }

    func testRerankAfterInterval() {
        var ranker = StableRanker(interval: 3)
        _ = ranker.orderedRows([row(1, cpu: 0.1), row(2, cpu: 0.9)],
                               sortedBy: cpuDescending, now: t0)
        let out = ranker.orderedRows([row(1, cpu: 0.9), row(2, cpu: 0.1)],
                                     sortedBy: cpuDescending, now: t0.addingTimeInterval(3.5))
        XCTAssertEqual(out.map(\.pid), [1, 2])
    }

    func testForceRerankAppliesImmediately() {
        var ranker = StableRanker(interval: 3)
        _ = ranker.orderedRows([row(1, cpu: 0.1), row(2, cpu: 0.9)],
                               sortedBy: cpuDescending, now: t0)
        let out = ranker.orderedRows([row(1, cpu: 0.9), row(2, cpu: 0.1)],
                                     sortedBy: cpuDescending,
                                     now: t0.addingTimeInterval(1), forceRerank: true)
        XCTAssertEqual(out.map(\.pid), [1, 2])
    }

    func testNewcomersAppendAtEndUntilRerank() {
        var ranker = StableRanker(interval: 3)
        _ = ranker.orderedRows([row(1, cpu: 0.1), row(2, cpu: 0.9)],
                               sortedBy: cpuDescending, now: t0)
        // pid 3 arrives with the highest CPU — it must NOT jump to the top yet.
        let out = ranker.orderedRows([row(1, cpu: 0.1), row(2, cpu: 0.9), row(3, cpu: 1.0)],
                                     sortedBy: cpuDescending, now: t0.addingTimeInterval(1))
        XCTAssertEqual(out.map(\.pid), [2, 1, 3])
    }

    func testDeadRowsDropOutImmediately() {
        var ranker = StableRanker(interval: 3)
        _ = ranker.orderedRows([row(1, cpu: 0.1), row(2, cpu: 0.9)],
                               sortedBy: cpuDescending, now: t0)
        let out = ranker.orderedRows([row(1, cpu: 0.1)],
                                     sortedBy: cpuDescending, now: t0.addingTimeInterval(1))
        XCTAssertEqual(out.map(\.pid), [1])
    }
}
