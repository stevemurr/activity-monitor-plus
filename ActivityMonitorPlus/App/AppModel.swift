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
    private let coordinator: SamplingCoordinator
    private var consumeTask: Task<Void, Never>?

    init(samplers: SamplerSet, autoStart: Bool = true) {
        coordinator = SamplingCoordinator(samplers: samplers)
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

    private func apply(_ update: SamplingUpdate) {
        let snapshot = update.snapshot
        if let logPath = ProcessInfo.processInfo.environment["AMP_DEBUG"] {
            let attributed = snapshot.cpu.processes.compactMap(\.cpuFraction).reduce(0, +)
            let line = "AMP_DEBUG apply: total=\(snapshot.cpu.totalUsedFraction) perProcSum=\(attributed) at \(snapshot.timestamp.timeIntervalSince1970)\n"
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                FileHandle.standardError.write(Data(line.utf8))
            }
        }
        cpu = snapshot.cpu
        donutSlices = CPUDonutSlices.compute(cpu: snapshot.cpu)
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
