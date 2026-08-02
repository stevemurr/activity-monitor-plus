import Foundation

/// One full 1 Hz sample of system state, emitted by the sampling coordinator.
struct SystemSnapshot: Sendable {
    var timestamp: Date
    var cpu: CPUSnapshot
    var memory: MemorySnapshot?
    var volumes: [VolumeInfo]
    var throughput: NetworkThroughput
}

struct CPUSnapshot: Sendable {
    /// False while a delta-based sampler is collecting its initial baseline.
    /// Fixture and other immediately meaningful samplers can keep the default.
    var isReady: Bool = true
    /// Fraction of total machine capacity in use (0...1), from host tick deltas.
    var totalUsedFraction: Double
    /// Activity-Monitor-style split of the total: user (incl. nice) and system.
    var userFraction: Double = 0
    var systemFraction: Double = 0
    var coreCount: Int
    var processes: [ProcessSample]

    var idleFraction: Double { max(0, 1 - totalUsedFraction) }
}

struct ProcessSample: Sendable, Identifiable {
    var pid: Int32
    var name: String
    /// Fraction of total machine capacity (0...1); nil when unreadable (EPERM on
    /// other users' processes).
    var cpuFraction: Double?
    var residentBytes: UInt64?
    var id: Int32 { pid }
}

struct MemorySnapshot: Sendable {
    var totalBytes: UInt64
    var appBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var usedBytes: UInt64 { appBytes + wiredBytes + compressedBytes }
    var freeBytes: UInt64 { totalBytes > usedBytes ? totalBytes - usedBytes : 0 }
    var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

struct VolumeInfo: Sendable, Identifiable {
    var path: String
    var name: String
    var totalBytes: UInt64
    var availableBytes: UInt64
    var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
    var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
    var id: String { path }
}

struct NetworkThroughput: Sendable {
    var bytesInPerSecond: Double
    var bytesOutPerSecond: Double
    static let zero = NetworkThroughput(bytesInPerSecond: 0, bytesOutPerSecond: 0)
}
