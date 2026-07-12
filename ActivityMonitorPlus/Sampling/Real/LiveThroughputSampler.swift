import Darwin
import Foundation

/// Whole-machine network throughput from interface byte counters
/// (getifaddrs / AF_LINK if_data), excluding loopback.
final class LiveThroughputSampler: ThroughputSampling {
    // if_data counters are 32-bit and wrap; track per interface and use
    // wrapping subtraction so a single wrap between samples stays correct.
    private var previousCounters: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var previousDate: Date?

    func sample() -> NetworkThroughput {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return .zero }
        defer { freeifaddrs(addrs) }

        var counters: [String: (rx: UInt32, tx: UInt32)] = [:]
        var pointer = addrs
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next
            guard let addr = interface.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPointer = interface.ifa_data else { continue }
            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            let existing = counters[name] ?? (0, 0)
            counters[name] = (existing.rx &+ data.ifi_ibytes,
                              existing.tx &+ data.ifi_obytes)
        }

        let now = Date()
        defer {
            previousCounters = counters
            previousDate = now
        }
        guard let previousDate else { return .zero }
        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0 else { return .zero }

        var deltaIn: UInt64 = 0
        var deltaOut: UInt64 = 0
        for (name, current) in counters {
            guard let previous = previousCounters[name] else { continue }
            deltaIn += UInt64(current.rx &- previous.rx)
            deltaOut += UInt64(current.tx &- previous.tx)
        }
        return NetworkThroughput(bytesInPerSecond: Double(deltaIn) / elapsed,
                                 bytesOutPerSecond: Double(deltaOut) / elapsed)
    }
}
