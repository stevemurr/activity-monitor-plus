import Foundation

/// Turns successive netstat snapshots into a stream of connection events.
/// Pure state machine — no clocks, no I/O — so it's directly unit-testable.
struct ConnectionDiffEngine {
    static let maxTrafficEventsPerTick = 100

    private var previous: [ConnectionKey: ConnectionSnapshot]?

    mutating func ingest(_ current: [ConnectionSnapshot], at date: Date) -> [ConnectionEvent] {
        let currentByKey = Dictionary(current.map { ($0.key, $0) },
                                      uniquingKeysWith: { a, b in
            a.rxBytes + a.txBytes >= b.rxBytes + b.txBytes ? a : b
        })

        // The first snapshot is the baseline: pre-existing connections are not
        // reported as "opened".
        guard let previous else {
            self.previous = currentByKey
            return []
        }

        var lifecycle: [ConnectionEvent] = []
        var traffic: [ConnectionEvent] = []

        for (key, snapshot) in currentByKey {
            guard let prior = previous[key] else {
                lifecycle.append(snapshot.event(.opened, at: date))
                if snapshot.rxBytes > 0 || snapshot.txBytes > 0 {
                    traffic.append(snapshot.event(.traffic, at: date,
                                                  bytesIn: snapshot.rxBytes,
                                                  bytesOut: snapshot.txBytes))
                }
                continue
            }
            if snapshot.rxBytes < prior.rxBytes || snapshot.txBytes < prior.txBytes {
                // Counter regression: the tuple was reused by a new connection.
                lifecycle.append(prior.event(.closed, at: date))
                lifecycle.append(snapshot.event(.opened, at: date))
                if snapshot.rxBytes > 0 || snapshot.txBytes > 0 {
                    traffic.append(snapshot.event(.traffic, at: date,
                                                  bytesIn: snapshot.rxBytes,
                                                  bytesOut: snapshot.txBytes))
                }
            } else {
                let deltaIn = snapshot.rxBytes - prior.rxBytes
                let deltaOut = snapshot.txBytes - prior.txBytes
                if deltaIn + deltaOut > 0 {
                    traffic.append(snapshot.event(.traffic, at: date,
                                                  bytesIn: deltaIn, bytesOut: deltaOut))
                }
            }
        }

        for (key, prior) in previous where currentByKey[key] == nil {
            lifecycle.append(prior.event(.closed, at: date))
        }

        // Cap traffic events per tick so a busy machine can't flood the log;
        // keep the largest movers.
        if traffic.count > Self.maxTrafficEventsPerTick {
            traffic.sort { $0.bytesIn + $0.bytesOut > $1.bytesIn + $1.bytesOut }
            traffic.removeSubrange(Self.maxTrafficEventsPerTick...)
        }

        self.previous = currentByKey

        // Deterministic ordering within a tick keeps the log stable.
        var events = lifecycle + traffic
        events.sort {
            ($0.processName, $0.remote, $0.kind.rawValue)
                < ($1.processName, $1.remote, $1.kind.rawValue)
        }
        return events
    }
}
