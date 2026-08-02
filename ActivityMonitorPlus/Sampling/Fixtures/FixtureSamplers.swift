import Foundation
import Synchronization

/// Deterministic samplers for UI tests (`--uitest-fixtures`). Names are
/// deliberately unmistakable so assertions can't collide with real system
/// state, and full data is available from the first tick (no warm-up).

/// Shared mutable state between fixture samplers and the fixture process
/// controller, so "quitting" a fixture process makes it disappear from
/// subsequent samples exactly like a real kill would.
final class FixtureProcessState: Sendable {
    private let killed = Mutex<Set<Int32>>([])

    func markKilled(_ pid: Int32) {
        killed.withLock { _ = $0.insert(pid) }
    }

    func isKilled(_ pid: Int32) -> Bool {
        killed.withLock { $0.contains(pid) }
    }
}

final class FixtureCPUSampler: CPUSampling {
    private let state: FixtureProcessState

    init(state: FixtureProcessState = FixtureProcessState()) {
        self.state = state
    }

    func sample() -> CPUSnapshot {
        var snapshot = CPUSnapshot(totalUsedFraction: 0.62, userFraction: 0.44, systemFraction: 0.18,
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
        snapshot.processes.removeAll { state.isKilled($0.pid) }
        return snapshot
    }
}

final class FixtureProcessController: ProcessControlling {
    private let state: FixtureProcessState

    init(state: FixtureProcessState) {
        self.state = state
    }

    func terminate(pid: Int32, force: Bool) -> TerminateOutcome {
        guard (101...107).contains(pid) else { return .notFound }
        // FixtureRootProc simulates a root-owned process.
        guard pid != 107 else { return .permissionDenied }
        state.markKilled(pid)
        return .success
    }

    func details(pid: Int32, name: String) -> ProcessDetails {
        ProcessDetails(pid: pid, name: name,
                       path: "/Applications/\(name).app/Contents/MacOS/\(name)",
                       parentPid: 1, user: "fixtureuser",
                       startDate: Date(timeIntervalSince1970: 1_783_880_000))
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

/// Returns a deterministic storage tree instantly (no filesystem walk), with
/// unmistakable "Fixture …" node names and sizes that leave a visible
/// "System / hidden space" remainder against the fixture volume's used space.
final class FixtureDiskScanner: DiskScanning {
    func scan(volumeRoot: URL, volumeName: String, usedBytes: UInt64,
              progress: @Sendable @escaping (ScanProgress) -> Void) async -> StorageScanResult {
        let root = volumeRoot.path
        var acc = ScanAccumulator()
        acc.addDirectory(path: root, parent: nil)

        let cap = StorageTree.defaultTopFilesPerDir
        let globalCap = StorageTree.defaultGlobalFileCap

        let movies = volumeRoot.appendingPathComponent("Fixture Movies")
        acc.addDirectory(path: movies.path, parent: root)
        acc.addFile(parent: movies.path, name: "BigMovie.mov",
                    bytes: 120_000_000_000, capPerDir: cap, globalCap: globalCap)
        acc.addFile(parent: movies.path, name: "SmallClip.mov",
                    bytes: 8_000_000_000, capPerDir: cap, globalCap: globalCap)
        let clips = movies.appendingPathComponent("Clips")
        acc.addDirectory(path: clips.path, parent: movies.path)
        acc.addFile(parent: clips.path, name: "clip1.mov",
                    bytes: 20_000_000_000, capPerDir: cap, globalCap: globalCap)

        let xcode = volumeRoot.appendingPathComponent("Fixture Xcode")
        acc.addDirectory(path: xcode.path, parent: root)
        acc.addFile(parent: xcode.path, name: "Xcode.xip",
                    bytes: 45_000_000_000, capPerDir: cap, globalCap: globalCap)

        let photos = volumeRoot.appendingPathComponent("Fixture Photos")
        acc.addDirectory(path: photos.path, parent: root)
        acc.addFile(parent: photos.path, name: "Library.photoslibrary",
                    bytes: 52_000_000_000, capPerDir: cap, globalCap: globalCap)

        // A folder with many children so drilling into it yields a legend well
        // past what fits on screen — the case that exposes the trailing-scrollbar
        // overlap. A directory caps stored files at 20, so we also add album
        // subfolders (kept up to 40 mixed children) to push the list long.
        let music = volumeRoot.appendingPathComponent("Fixture Music")
        acc.addDirectory(path: music.path, parent: root)
        for i in 1...16 {
            let album = music.appendingPathComponent(String(format: "Fixture Album %02d", i))
            acc.addDirectory(path: album.path, parent: music.path)
            acc.addFile(parent: album.path, name: "album.m4a",
                        bytes: UInt64((17 - i) * 100_000_000),
                        capPerDir: cap, globalCap: globalCap)
        }
        for i in 1...16 {
            acc.addFile(parent: music.path,
                        name: String(format: "FixtureTrack-%02d.mp3", i),
                        bytes: UInt64((17 - i) * 10_000_000),
                        capPerDir: cap, globalCap: globalCap)
        }

        acc.addFile(parent: root, name: "fixture-readme.txt",
                    bytes: 1_000_000, capPerDir: cap, globalCap: globalCap)

        progress(ScanProgress(filesScanned: acc.fileCount, bytesScanned: acc.scannedBytes))
        let tree = StorageTree.build(rootPath: root, rootName: volumeName,
                                     accumulator: acc, usedBytes: usedBytes)
        return StorageScanResult(root: tree, scannedBytes: acc.scannedBytes,
                                 fileCount: acc.fileCount, deniedCount: 0,
                                 cancelled: false, hitFileCap: false)
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
