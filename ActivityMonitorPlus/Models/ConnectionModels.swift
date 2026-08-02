import Foundation

enum NetProto: String, Sendable {
    case tcp, udp
}

/// Identity of a socket across snapshots. The pid is part of the key because
/// SO_REUSEPORT lets several processes share one local/remote tuple.
struct ConnectionKey: Hashable, Sendable {
    var proto: NetProto
    var local: String
    var remote: String
    var pid: Int32
}

/// One row of `netstat -anv` output at a point in time. Byte counters are
/// cumulative for the socket's lifetime.
struct ConnectionSnapshot: Sendable {
    var key: ConnectionKey
    var processName: String
    /// TCP state (ESTABLISHED, LISTEN, ...); nil for UDP.
    var state: String?
    var rxBytes: UInt64
    var txBytes: UInt64
    /// False when the native libproc fallback can identify the socket but the
    /// OS does not expose its byte counters through that API.
    var byteCountersAvailable: Bool = true
}

struct ConnectionEvent: Identifiable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        case opened = "Opened"
        case closed = "Closed"
        case traffic = "Traffic"
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
    let processName: String
    let pid: Int32
    let local: String
    let remote: String
    let proto: NetProto
    /// For .traffic: bytes moved during the sample interval.
    /// For .opened/.closed: the socket's cumulative counters at that moment.
    let bytesIn: UInt64
    let bytesOut: UInt64
}

extension ConnectionSnapshot {
    func event(_ kind: ConnectionEvent.Kind, at date: Date,
               bytesIn: UInt64? = nil, bytesOut: UInt64? = nil) -> ConnectionEvent {
        ConnectionEvent(id: UUID(), timestamp: date, kind: kind,
                        processName: processName, pid: key.pid,
                        local: key.local, remote: key.remote, proto: key.proto,
                        bytesIn: bytesIn ?? rxBytes, bytesOut: bytesOut ?? txBytes)
    }
}
