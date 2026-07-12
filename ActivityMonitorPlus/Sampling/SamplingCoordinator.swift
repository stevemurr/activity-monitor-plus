import Foundation

struct SamplingUpdate: Sendable {
    var snapshot: SystemSnapshot
    var connectionEvents: [ConnectionEvent]
}

/// Owns the samplers and runs the 1 Hz loop, publishing updates as an
/// AsyncStream. Samplers are created inside the actor and never leave it.
actor SamplingCoordinator {
    private let samplers: SamplerSet
    private var loop: Task<Void, Never>?

    init(samplers: SamplerSet) {
        self.samplers = samplers
    }

    func start(interval: Duration = .seconds(1)) -> AsyncStream<SamplingUpdate> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: SamplingUpdate.self, bufferingPolicy: .bufferingNewest(2))
        loop?.cancel()
        loop = Task { await run(continuation: continuation, interval: interval) }
        return stream
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func run(continuation: AsyncStream<SamplingUpdate>.Continuation,
                     interval: Duration) async {
        let cpu = samplers.makeCPU()
        let memory = samplers.makeMemory()
        let storage = samplers.makeStorage()
        let throughput = samplers.makeThroughput()
        let connections = samplers.makeConnections()
        var diffEngine = ConnectionDiffEngine()

        while !Task.isCancelled {
            let now = Date()
            let snapshot = SystemSnapshot(timestamp: now,
                                          cpu: cpu.sample(),
                                          memory: memory.sample(),
                                          volumes: storage.sample(),
                                          throughput: throughput.sample())
            let sockets = await connections.snapshot()
            let events = diffEngine.ingest(sockets, at: now)
            continuation.yield(SamplingUpdate(snapshot: snapshot,
                                              connectionEvents: events))
            do {
                try await Task.sleep(for: interval)
            } catch {
                break
            }
        }
        continuation.finish()
    }
}
