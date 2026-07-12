import Foundation
import Observation

struct ThroughputPoint: Identifiable, Sendable {
    let timestamp: Date
    let bytesInPerSecond: Double
    let bytesOutPerSecond: Double
    var id: Date { timestamp }
}

@MainActor @Observable
final class AppModel {
    private(set) var cpu = CPUSnapshot(totalUsedFraction: 0, coreCount: 1, processes: [])
    private(set) var donutSlices: [DonutSlice] = []
    /// Bumped once per sampling tick; views observe this to refresh derived state.
    private(set) var lastUpdate = Date.distantPast
    private(set) var memory: MemorySnapshot?
    private(set) var volumes: [VolumeInfo] = []
    private(set) var throughput = NetworkThroughput.zero
    private(set) var throughputHistory: [ThroughputPoint] = []
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
    private var consumeTask: Task<Void, Never>?

    init(samplers: SamplerSet, autoStart: Bool = true) {
        coordinator = SamplingCoordinator(samplers: samplers)
        processController = samplers.processController
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
        Array(connectionEvents.lazy.filter { $0.pid == pid }.prefix(limit))
    }

    private func apply(_ update: SamplingUpdate) {
        let snapshot = update.snapshot
        DebugLog.write("apply total=\(snapshot.cpu.totalUsedFraction) at \(snapshot.timestamp.timeIntervalSince1970)")
        var cpuSnapshot = snapshot.cpu
        cpuSnapshot.processes = smoother.smooth(cpuSnapshot.processes)
        cpu = cpuSnapshot
        donutSlices = CPUDonutSlices.compute(cpu: cpuSnapshot)
        lastUpdate = snapshot.timestamp
        memory = snapshot.memory
        volumes = snapshot.volumes
        throughput = snapshot.throughput
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
        connectionEvents = eventLog.elements.reversed()
    }
}
