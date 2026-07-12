import Foundation

/// Sampler seam: real implementations read the live system; fixture
/// implementations return scripted data for deterministic UI tests.
/// The synchronous samplers are stateful (they keep previous counters) and are
/// confined to the SamplingCoordinator actor — only snapshots cross it.

protocol CPUSampling: AnyObject {
    func sample() -> CPUSnapshot
}

protocol MemorySampling: AnyObject {
    func sample() -> MemorySnapshot?
}

protocol StorageSampling: AnyObject {
    func sample() -> [VolumeInfo]
}

protocol ThroughputSampling: AnyObject {
    func sample() -> NetworkThroughput
}

/// Async because the live implementation spawns netstat. Sendable because the
/// call suspends off the coordinator; implementations synchronize any state.
protocol ConnectionSnapshotProviding: Sendable {
    func snapshot() async -> [ConnectionSnapshot]
}

/// Factories rather than instances so the samplers are constructed inside the
/// coordinator actor and never cross an isolation boundary.
struct SamplerSet: Sendable {
    var makeCPU: @Sendable () -> any CPUSampling
    var makeMemory: @Sendable () -> any MemorySampling
    var makeStorage: @Sendable () -> any StorageSampling
    var makeThroughput: @Sendable () -> any ThroughputSampling
    var makeConnections: @Sendable () -> any ConnectionSnapshotProviding

    static func live() -> SamplerSet {
        SamplerSet(makeCPU: { LiveCPUSampler() },
                   makeMemory: { LiveMemorySampler() },
                   makeStorage: { LiveStorageSampler() },
                   makeThroughput: { LiveThroughputSampler() },
                   makeConnections: { NetstatRunner() })
    }

    static func fixtures() -> SamplerSet {
        SamplerSet(makeCPU: { FixtureCPUSampler() },
                   makeMemory: { FixtureMemorySampler() },
                   makeStorage: { FixtureStorageSampler() },
                   makeThroughput: { FixtureThroughputSampler() },
                   makeConnections: { FixtureConnectionProvider() })
    }
}
