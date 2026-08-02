import XCTest
@testable import ActivityMonitorPlus

/// Sanity checks that the real system APIs are wired correctly. These sample
/// the live machine, so they assert invariants, not exact values.
final class LiveSamplerSmokeTests: XCTestCase {
    func testLiveCPUSamplerProducesPlausibleData() throws {
        let sampler = LiveCPUSampler()
        _ = sampler.sample() // baseline
        Thread.sleep(forTimeInterval: 0.3)
        let snapshot = sampler.sample()

        XCTAssertGreaterThan(snapshot.coreCount, 0)
        XCTAssertTrue((0...1).contains(snapshot.totalUsedFraction))
        XCTAssertGreaterThan(snapshot.processes.count, 10)
        // Our own process must be attributable (same UID).
        let me = snapshot.processes.first {
            $0.pid == ProcessInfo.processInfo.processIdentifier
        }
        XCTAssertNotNil(me)
        XCTAssertNotNil(try XCTUnwrap(me).cpuFraction)
        for process in snapshot.processes {
            if let fraction = process.cpuFraction {
                XCTAssertTrue((0...1.5).contains(fraction),
                              "\(process.name) fraction \(fraction)")
            }
        }
    }

    func testLiveMemorySamplerProducesPlausibleData() throws {
        let snapshot = try XCTUnwrap(LiveMemorySampler().sample())
        XCTAssertGreaterThan(snapshot.totalBytes, 1_000_000_000)
        XCTAssertGreaterThan(snapshot.usedBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.usedBytes, snapshot.totalBytes)
    }

    func testLiveStorageSamplerFindsBootVolume() {
        let volumes = LiveStorageSampler().sample()
        XCTAssertFalse(volumes.isEmpty)
        let boot = volumes.first { $0.path == "/" }
        XCTAssertNotNil(boot)
        XCTAssertGreaterThan(boot?.totalBytes ?? 0, 0)
    }

    func testLiveThroughputSamplerReturnsNonNegativeRates() {
        let sampler = LiveThroughputSampler()
        _ = sampler.sample() // baseline
        Thread.sleep(forTimeInterval: 0.2)
        let rate = sampler.sample()
        XCTAssertGreaterThanOrEqual(rate.bytesInPerSecond, 0)
        XCTAssertGreaterThanOrEqual(rate.bytesOutPerSecond, 0)
    }

    func testNetstatRunnerParsesLiveSocketTable() async {
        let rows = await NetstatRunner().snapshot()
        XCTAssertFalse(rows.isEmpty,
                       "live sampler returned no usable TCP/UDP sockets")
        // Every parsed row must be structurally sane.
        for row in rows {
            XCTAssertFalse(row.key.local.isEmpty)
            XCTAssertNotEqual(row.state, "LISTEN") // noise filter applied
        }
    }
}

extension LiveSamplerSmokeTests {
    func testHostTotalMatchesRealisticIdleLoad() {
        let sampler = LiveCPUSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 1.0)
        let snapshot = sampler.sample()
        print(">>> totalUsedFraction over 1s:", snapshot.totalUsedFraction)
        let attributed = snapshot.processes.compactMap(\.cpuFraction).reduce(0, +)
        print(">>> sum of per-process fractions:", attributed)
        XCTAssertLessThan(snapshot.totalUsedFraction, 0.9,
                          "host total implausibly high on an idle machine")
        // The user/system split must compose the total exactly.
        XCTAssertEqual(snapshot.userFraction + snapshot.systemFraction,
                       snapshot.totalUsedFraction, accuracy: 1e-9)
        XCTAssertGreaterThan(snapshot.userFraction, 0)
        XCTAssertGreaterThan(snapshot.systemFraction, 0)
    }
}
