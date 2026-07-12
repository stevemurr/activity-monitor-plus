import XCTest
@testable import ActivityMonitorPlus

final class CPUDonutSlicesTests: XCTestCase {
    private func cpu(total: Double, processes: [(String, Double?)]) -> CPUSnapshot {
        CPUSnapshot(totalUsedFraction: total, coreCount: 8,
                    processes: processes.enumerated().map { i, p in
                        ProcessSample(pid: Int32(i + 1), name: p.0,
                                      cpuFraction: p.1, residentBytes: nil)
                    })
    }

    func testTopFivePlusOtherPlusIdle() {
        let snapshot = cpu(total: 0.62, processes: [
            ("A", 0.30), ("B", 0.15), ("C", 0.08), ("D", 0.04), ("E", 0.02),
            ("F", 0.01), ("G", 0.005),
        ])
        let slices = CPUDonutSlices.compute(cpu: snapshot)
        XCTAssertEqual(slices.map(\.label), ["A", "B", "C", "D", "E", "Other", "Idle"])
        // Other = 0.62 − 0.59; everything sums to 1.
        XCTAssertEqual(slices[5].fraction, 0.03, accuracy: 1e-9)
        XCTAssertEqual(slices[6].fraction, 0.38, accuracy: 1e-9)
        XCTAssertEqual(slices.map(\.fraction).reduce(0, +), 1.0, accuracy: 1e-9)
    }

    func testUnreadableProcessesFoldIntoOther() {
        let snapshot = cpu(total: 0.5, processes: [
            ("A", 0.10), ("RootProc", nil),
        ])
        let slices = CPUDonutSlices.compute(cpu: snapshot)
        XCTAssertEqual(slices.map(\.label), ["A", "Other", "Idle"])
        XCTAssertEqual(slices[1].fraction, 0.40, accuracy: 1e-9)
    }

    func testProcessSumExceedingHostTotalIsClamped() {
        // Non-atomic sampling can make per-process sums exceed the host total.
        let snapshot = cpu(total: 0.20, processes: [
            ("A", 0.15), ("B", 0.10), ("C", 0.08),
        ])
        let slices = CPUDonutSlices.compute(cpu: snapshot)
        XCTAssertEqual(slices.map(\.fraction).reduce(0, +), 1.0, accuracy: 1e-9)
        XCTAssertFalse(slices.contains { $0.fraction < 0 })
        // B got clamped to the remaining budget; C contributed nothing.
        XCTAssertEqual(slices.map(\.label), ["A", "B", "Idle"])
        XCTAssertEqual(slices[1].fraction, 0.05, accuracy: 1e-9)
    }

    func testIdleMachine() {
        let slices = CPUDonutSlices.compute(cpu: cpu(total: 0, processes: []))
        XCTAssertEqual(slices.map(\.label), ["Idle"])
        XCTAssertEqual(slices[0].fraction, 1.0, accuracy: 1e-9)
    }
}
