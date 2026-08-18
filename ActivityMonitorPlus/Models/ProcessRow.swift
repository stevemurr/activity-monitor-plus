import Foundation

/// Row model for the process table.
struct ProcessRow: Identifiable, Sendable {
    let pid: Int32
    let name: String
    let cpuFraction: Double?
    let residentBytes: UInt64?
    var id: Int32 { pid }
    // Unreadable (nil) values sort below every real value.
    var cpuSortKey: Double { cpuFraction ?? -1 }
    var memorySortKey: Double { residentBytes.map(Double.init) ?? -1 }

    init(_ sample: ProcessSample) {
        pid = sample.pid
        name = sample.name
        cpuFraction = sample.cpuFraction
        residentBytes = sample.residentBytes
    }

    init(pid: Int32, name: String, cpuFraction: Double?, residentBytes: UInt64?) {
        self.pid = pid
        self.name = name
        self.cpuFraction = cpuFraction
        self.residentBytes = residentBytes
    }
}

/// Exponential moving average over per-pid CPU, so displayed values (and the
/// donut) don't twitch with every 1s sample.
struct ProcessSmoother {
    var alpha: Double = 0.35
    private var smoothed: [Int32: Double] = [:]

    mutating func smooth(_ samples: [ProcessSample]) -> [ProcessSample] {
        var seen = Set<Int32>()
        seen.reserveCapacity(samples.count)
        let result = samples.map { sample in
            seen.insert(sample.pid)
            guard let raw = sample.cpuFraction else { return sample }
            let value = smoothed[sample.pid].map { alpha * raw + (1 - alpha) * $0 } ?? raw
            smoothed[sample.pid] = value
            var out = sample
            out.cpuFraction = value
            return out
        }
        smoothed = smoothed.filter { seen.contains($0.key) }
        return result
    }
}

/// `sorted(using:)` routes every comparison through an existential
/// `SortComparator`, and `KeyPathComparator`'s default String comparator is
/// `.localizedStandard` (full ICU collation). On ~1000 live processes that
/// measures 10.5 ms for the CPU sort and 30.9 ms for the name sort, versus
/// 0.06 ms and 3.3 ms for the equivalent concrete sorts below — all of it on
/// the main thread, on every re-rank and every sort/scope click.
///
/// The Table's `sortOrder` binding still speaks `KeyPathComparator`, so this
/// recognizes the four sortable columns and falls back to `sorted(using:)` for
/// anything it doesn't know.
extension Array where Element == ProcessRow {
    func fastSorted(using comparators: [KeyPathComparator<ProcessRow>]) -> [ProcessRow] {
        // Only one comparator means no tiebreakers to honor; anything else
        // goes down the general path rather than silently dropping them.
        guard comparators.count == 1, let primary = comparators.first else {
            return sorted(using: comparators)
        }
        let ascending = primary.order == .forward

        func by<Value: Comparable>(_ key: (ProcessRow) -> Value) -> [ProcessRow] {
            ascending ? sorted { key($0) < key($1) } : sorted { key($0) > key($1) }
        }

        switch primary.keyPath {
        case \ProcessRow.cpuSortKey: return by(\.cpuSortKey)
        case \ProcessRow.memorySortKey: return by(\.memorySortKey)
        case \ProcessRow.pid: return by(\.pid)
        case \ProcessRow.name:
            // Decorate/sort/undecorate: fold case once per row rather than
            // once per comparison. Case-insensitive rather than the localized
            // collation `sorted(using:)` would apply — ordering differs only
            // for non-ASCII names and embedded digits.
            let decorated = map { ($0.name.lowercased(), $0) }
            let ordered = ascending
                ? decorated.sorted { $0.0 < $1.0 }
                : decorated.sorted { $0.0 > $1.0 }
            return ordered.map(\.1)
        default:
            return sorted(using: comparators)
        }
    }
}

/// Keeps the table's row order frozen between periodic re-ranks so rows stop
/// oscillating: values update in place every tick, positions change at most
/// once per `interval` (or immediately when the user changes the sort).
struct StableRanker {
    var interval: TimeInterval = 3
    private var rankedPids: [Int32] = []
    private var lastRankTime: Date = .distantPast

    mutating func orderedRows(_ rows: [ProcessRow],
                              sortedBy comparators: [KeyPathComparator<ProcessRow>],
                              now: Date,
                              forceRerank: Bool = false) -> [ProcessRow] {
        if forceRerank || rankedPids.isEmpty
            || now.timeIntervalSince(lastRankTime) >= interval {
            let sorted = rows.fastSorted(using: comparators)
            rankedPids = sorted.map(\.pid)
            lastRankTime = now
            return sorted
        }

        var byPid = Dictionary(rows.map { ($0.pid, $0) },
                               uniquingKeysWith: { a, _ in a })
        var ordered: [ProcessRow] = []
        ordered.reserveCapacity(rows.count)
        for pid in rankedPids {
            if let row = byPid.removeValue(forKey: pid) {
                ordered.append(row)
            }
        }
        // Processes that appeared since the last rank go at the end (sorted
        // among themselves) instead of jumping into the middle.
        if !byPid.isEmpty {
            let newcomers = rows.filter { byPid[$0.pid] != nil }.fastSorted(using: comparators)
            ordered.append(contentsOf: newcomers)
        }
        return ordered
    }
}
