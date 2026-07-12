import Foundation

struct DonutSlice: Identifiable, Equatable, Sendable {
    enum Category: Equatable, Sendable {
        case process(pid: Int32)
        case other
        case idle
    }

    let category: Category
    let label: String
    let fraction: Double

    var id: String {
        switch category {
        case .process(let pid): "process.\(pid)"
        case .other: "other"
        case .idle: "idle"
        }
    }
}

enum CPUDonutSlices {
    /// Top-N process slices + "Other" + "Idle", summing to 1. "Other" is the
    /// host-level total minus the attributed top slices, so it absorbs both
    /// below-cut processes and ones libproc couldn't read (EPERM → nil).
    static func compute(cpu: CPUSnapshot, topN: Int = 5) -> [DonutSlice] {
        let total = min(max(cpu.totalUsedFraction, 0), 1)
        let ranked = cpu.processes
            .compactMap { process in process.cpuFraction.map { (process, $0) } }
            .filter { $0.1 > 0.0005 }
            .sorted { $0.1 > $1.1 }

        var slices: [DonutSlice] = []
        var attributed = 0.0
        for (process, fraction) in ranked.prefix(topN) {
            // Per-process and host samples aren't atomic; never exceed the host total.
            let clamped = min(fraction, total - attributed)
            guard clamped > 0 else { break }
            slices.append(DonutSlice(category: .process(pid: process.pid),
                                     label: process.name, fraction: clamped))
            attributed += clamped
        }

        let other = total - attributed
        if other > 0.0005 {
            slices.append(DonutSlice(category: .other, label: "Other", fraction: other))
        }
        slices.append(DonutSlice(category: .idle, label: "Idle", fraction: max(0, 1 - total)))
        return slices
    }
}
