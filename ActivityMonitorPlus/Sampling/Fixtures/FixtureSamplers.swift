import Foundation
import Synchronization

/// Deterministic samplers for UI tests (`--uitest-fixtures`). Names are
/// deliberately unmistakable so assertions can't collide with real system
/// state, and full data is available from the first tick (no warm-up).

final class FixtureCPUSampler: CPUSampling {
    func sample() -> CPUSnapshot {
        CPUSnapshot(totalUsedFraction: 0.62, userFraction: 0.44, systemFraction: 0.18,
                    coreCount: 8, processes: [
            ProcessSample(pid: 101, name: "FixtureProcA", cpuFraction: 0.30,
                          residentBytes: 1_200_000_000),
            ProcessSample(pid: 102, name: "FixtureProcB", cpuFraction: 0.15,
                          residentBytes: 800_000_000),
            ProcessSample(pid: 103, name: "FixtureProcC", cpuFraction: 0.08,
                          residentBytes: 350_000_000),
            ProcessSample(pid: 104, name: "FixtureProcD", cpuFraction: 0.04,
                          residentBytes: 150_000_000),
            ProcessSample(pid: 105, name: "FixtureProcE", cpuFraction: 0.02,
                          residentBytes: 90_000_000),
            ProcessSample(pid: 106, name: "FixtureProcF", cpuFraction: 0.01,
                          residentBytes: 40_000_000),
            ProcessSample(pid: 107, name: "FixtureRootProc", cpuFraction: nil,
                          residentBytes: nil),
        ])
    }
}

final class FixtureMemorySampler: MemorySampling {
    func sample() -> MemorySnapshot? {
        MemorySnapshot(totalBytes: 32_000_000_000,
                       appBytes: 12_000_000_000,
                       wiredBytes: 4_000_000_000,
                       compressedBytes: 2_000_000_000)
    }
}

final class FixtureStorageSampler: StorageSampling {
    func sample() -> [VolumeInfo] {
        [
            VolumeInfo(path: "/", name: "Fixture HD",
                       totalBytes: 500_000_000_000, availableBytes: 200_000_000_000),
            VolumeInfo(path: "/Volumes/Fixture External", name: "Fixture External",
                       totalBytes: 2_000_000_000_000, availableBytes: 1_500_000_000_000),
        ]
    }
}

final class FixtureThroughputSampler: ThroughputSampling {
    func sample() -> NetworkThroughput {
        NetworkThroughput(bytesInPerSecond: 1_300_000, bytesOutPerSecond: 240_000)
    }
}

/// Scripted socket-table sequence. Relative to the diff engine's baseline at
/// tick 0, it produces: an Opened event, then a Traffic event (12.3 KB in /
/// 4.5 KB out), then a Closed event, repeating every 6 ticks.
final class FixtureConnectionProvider: ConnectionSnapshotProviding {
    private let tick = Mutex(0)

    func snapshot() async -> [ConnectionSnapshot] {
        let current = tick.withLock { value in
            let result = value
            value += 1
            return result
        }
        let connection = { (rx: UInt64, tx: UInt64) in
            ConnectionSnapshot(
                key: ConnectionKey(proto: .tcp,
                                   local: "192.168.1.10.50000",
                                   remote: "93.184.216.34.443",
                                   pid: 4242),
                processName: "FixtureNet", state: "ESTABLISHED",
                rxBytes: rx, txBytes: tx)
        }
        switch current % 6 {
        case 2: return [connection(0, 0)]           // → Opened
        case 3: return [connection(12_300, 4_500)]  // → Traffic
        default: return []                          // tick after 3 → Closed
        }
    }
}
