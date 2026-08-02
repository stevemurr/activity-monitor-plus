import Foundation

struct NetworkProcessKey: Hashable, Sendable {
    let name: String
    let pid: Int32
}

/// A process header or one of the connection events nested beneath it.
struct NetworkLogRow: Identifiable, Sendable {
    enum ID: Hashable, Sendable {
        case process(NetworkProcessKey)
        case event(UUID)
    }

    let id: ID
    let process: NetworkProcessKey
    let event: ConnectionEvent?
    let eventCount: Int
    let lastActivity: Date
    let children: [NetworkLogRow]?

    var isProcessGroup: Bool { event == nil }

    static func groupedByProcess(_ events: [ConnectionEvent]) -> [NetworkLogRow] {
        Dictionary(grouping: events) {
            NetworkProcessKey(name: $0.processName, pid: $0.pid)
        }
        .map { process, processEvents in
            let sortedEvents = processEvents.sorted {
                if $0.timestamp != $1.timestamp {
                    return $0.timestamp > $1.timestamp
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            let children = sortedEvents.map { event in
                NetworkLogRow(
                    id: .event(event.id),
                    process: process,
                    event: event,
                    eventCount: 0,
                    lastActivity: event.timestamp,
                    children: nil)
            }

            return NetworkLogRow(
                id: .process(process),
                process: process,
                event: nil,
                eventCount: children.count,
                lastActivity: sortedEvents[0].timestamp,
                children: children)
        }
        .sorted {
            let nameOrder = $0.process.name.localizedCaseInsensitiveCompare($1.process.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return $0.process.pid < $1.process.pid
        }
    }
}
