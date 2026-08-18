import Foundation
import Observation

struct ThroughputPoint: Identifiable, Sendable {
    let timestamp: Date
    let bytesInPerSecond: Double
    let bytesOutPerSecond: Double
    var id: Date { timestamp }
}

struct SystemHistoryPoint: Identifiable, Sendable {
    let timestamp: Date
    let cpuUsedFraction: Double
    let userFraction: Double
    let systemFraction: Double
    let memoryUsedBytes: UInt64?
    var id: Date { timestamp }
}

@MainActor @Observable
final class AppModel {
    /// SwiftUI's macOS Table eagerly does substantial work per row on every
    /// update. Keep the live one-second refresh responsive while retaining the
    /// larger eventLog for history and process inspection.
    private static let displayedNetworkEventLimit = 300

    private(set) var cpu = CPUSnapshot(
        isReady: false,
        totalUsedFraction: 0,
        coreCount: 1,
        processes: []
    )
    private(set) var donutSlices: [DonutSlice] = []
    /// Highest-CPU processes, ranked once per tick. The Overview card and the
    /// menu-bar panel each read this several times while building their body;
    /// deriving it there re-filtered and re-sorted all ~1000 samples per read.
    private(set) var topProcesses: [ProcessSample] = []
    /// Bumped once per sampling tick; views observe this to refresh derived state.
    private(set) var lastUpdate = Date.distantPast
    private(set) var memory: MemorySnapshot?
    private(set) var volumes: [VolumeInfo] = []
    private(set) var throughput = NetworkThroughput.zero
    private(set) var throughputHistory: [ThroughputPoint] = []
    private(set) var systemHistory: [SystemHistoryPoint] = []
    /// Current non-listening, non-loopback sockets from the latest sample.
    /// Kept separately from the bounded/pausable event log so automation and
    /// status queries always describe live network state.
    private(set) var currentConnections: [ConnectionSnapshot] = []
    /// Deduplicated off the UI actor once per sampling tick.
    private(set) var activeConnectionCount = 0
    /// Newest-first, for the network log table.
    private(set) var connectionEvents: [ConnectionEvent] = []
    var isNetworkLogPaused = false {
        didSet {
            if !isNetworkLogPaused { refreshDisplayedEvents() }
        }
    }

    private var eventLog = RingBuffer<ConnectionEvent>(capacity: 2000)
    private var smoother = ProcessSmoother()
    private let coordinator: SamplingCoordinator
    private let processController: any ProcessControlling
    /// On-demand disk-usage scanner for the storage breakdown sheet. Stateless
    /// and `Sendable`, so a single instance from the sampler seam is enough.
    let diskScanner: any DiskScanning
    private var consumeTask: Task<Void, Never>?

    init(samplers: SamplerSet, autoStart: Bool = true) {
        coordinator = SamplingCoordinator(samplers: samplers)
        processController = samplers.processController
        diskScanner = samplers.makeDiskScanner()
        // Hosted unit tests launch the app binary; don't sample the real
        // system underneath them.
        let underUnitTest =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if autoStart && !underUnitTest {
            start()
        }
    }

    func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { [weak self, coordinator] in
            let stream = await coordinator.start()
            for await update in stream {
                guard let self else { break }
                self.apply(update)
            }
        }
    }

    func stop() {
        consumeTask?.cancel()
        consumeTask = nil
        Task { [coordinator] in await coordinator.stop() }
    }

    func shutdown() async {
        consumeTask?.cancel()
        consumeTask = nil
        await coordinator.stop()
    }

    func clearNetworkLog() {
        eventLog.removeAll()
        connectionEvents = []
    }

    /// Returns human-readable error strings for processes that could not be
    /// terminated (empty on full success).
    func terminate(pids: [(pid: Int32, name: String)], force: Bool) -> [String] {
        pids.compactMap { process in
            let outcome = processController.terminate(pid: process.pid, force: force)
            return outcome.errorDescription.map { "\(process.name): \($0)" }
        }
    }

    func details(pid: Int32, name: String) -> ProcessDetails {
        processController.details(pid: pid, name: name)
    }

    func recentEvents(forPid pid: Int32, limit: Int = 8) -> [ConnectionEvent] {
        eventLog.newestFirst(limit: limit) { $0.pid == pid }
    }

    private func apply(_ update: SamplingUpdate) {
        let snapshot = update.snapshot
        DebugLog.write("apply total=\(snapshot.cpu.totalUsedFraction) at \(snapshot.timestamp.timeIntervalSince1970)")
        var cpuSnapshot = snapshot.cpu
        cpuSnapshot.processes = smoother.smooth(cpuSnapshot.processes)
        cpu = cpuSnapshot
        donutSlices = CPUDonutSlices.compute(cpu: cpuSnapshot)
        topProcesses = Array(cpuSnapshot.processes
            .filter { $0.cpuFraction != nil }
            .sorted { ($0.cpuFraction ?? 0) > ($1.cpuFraction ?? 0) }
            .prefix(3))
        lastUpdate = snapshot.timestamp
        memory = snapshot.memory
        volumes = snapshot.volumes
        throughput = snapshot.throughput
        currentConnections = update.connections
        activeConnectionCount = update.activeConnectionCount
        systemHistory.append(SystemHistoryPoint(
            timestamp: snapshot.timestamp,
            cpuUsedFraction: snapshot.cpu.totalUsedFraction,
            userFraction: snapshot.cpu.userFraction,
            systemFraction: snapshot.cpu.systemFraction,
            memoryUsedBytes: snapshot.memory?.usedBytes))
        if systemHistory.count > 60 {
            systemHistory.removeFirst(systemHistory.count - 60)
        }
        throughputHistory.append(ThroughputPoint(
            timestamp: snapshot.timestamp,
            bytesInPerSecond: snapshot.throughput.bytesInPerSecond,
            bytesOutPerSecond: snapshot.throughput.bytesOutPerSecond))
        if throughputHistory.count > 60 {
            throughputHistory.removeFirst(throughputHistory.count - 60)
        }

        // Keep collecting while paused; just freeze what's displayed.
        eventLog.append(contentsOf: update.connectionEvents)
        if !isNetworkLogPaused && !update.connectionEvents.isEmpty {
            refreshDisplayedEvents()
        }
    }

    private func refreshDisplayedEvents() {
        connectionEvents = eventLog.newestFirst(limit: Self.displayedNetworkEventLimit)
    }
}
