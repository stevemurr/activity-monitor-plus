import Foundation

/// Parses `netstat -anv -p tcp|udp` output.
///
/// Layout notes (validated against macOS 27):
/// - Header names two-word columns ("Local Address"), so fields are anchored
///   positionally: proto/recvq/sendq/local/foreign from the left.
/// - UDP rows omit the `(state)` column value entirely.
/// - The `process:pid` field can contain spaces ("Codex (Service):21223"), so
///   its end is found by the last token matching `…:<digits>`; everything
///   after it is numeric/hex bookkeeping columns.
enum NetstatParser {
    /// Returns [] when the output doesn't look like the expected layout
    /// (defense against column drift across OS builds).
    static func parse(_ output: String) -> [ConnectionSnapshot] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard let headerIndex = lines.firstIndex(where: { $0.hasPrefix("Proto") }) else { return [] }
        let header = lines[headerIndex]
        guard header.contains("rxbytes"), header.contains("txbytes"),
              header.contains("process:pid") else { return [] }

        var result: [ConnectionSnapshot] = []
        for line in lines[(headerIndex + 1)...] {
            if let snapshot = parseRow(line) {
                result.append(snapshot)
            }
        }
        return result
    }

    private static func parseRow(_ line: Substring) -> ConnectionSnapshot? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 12 else { return nil }

        let proto: NetProto
        if tokens[0].hasPrefix("tcp") { proto = .tcp }
        else if tokens[0].hasPrefix("udp") { proto = .udp }
        else { return nil }

        let local = tokens[3]
        let remote = tokens[4]

        var state: String?
        var index = 5
        if proto == .tcp, UInt64(tokens[5]) == nil {
            state = tokens[5]
            index = 6
        }

        guard tokens.count >= index + 4,
              let rx = UInt64(tokens[index]),
              let tx = UInt64(tokens[index + 1]) else { return nil }

        // Skip rhiwat/shiwat, then find where process:pid ends.
        let rest = Array(tokens[(index + 4)...])
        var processEnd: Int?
        for (i, token) in rest.enumerated() where endsInColonDigits(token) {
            processEnd = i
        }

        var name = "unknown"
        var pid: Int32 = 0
        if let processEnd {
            let field = rest[...processEnd].joined(separator: " ")
            if let colon = field.lastIndex(of: ":") {
                name = String(field[..<colon])
                pid = Int32(field[field.index(after: colon)...]) ?? 0
            }
        }

        return ConnectionSnapshot(
            key: ConnectionKey(proto: proto, local: local, remote: remote, pid: pid),
            processName: name, state: state, rxBytes: rx, txBytes: tx)
    }

    private static func endsInColonDigits(_ token: String) -> Bool {
        guard let colon = token.lastIndex(of: ":") else { return false }
        let digits = token[token.index(after: colon)...]
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    /// Rows that are noise for a request log: listeners, idle wildcard UDP
    /// sockets, and purely local (loopback) connections.
    static func filterNoise(_ snapshots: [ConnectionSnapshot]) -> [ConnectionSnapshot] {
        snapshots.filter { snapshot in
            if snapshot.state == "LISTEN" { return false }
            if snapshot.key.remote == "*.*" && snapshot.rxBytes == 0 && snapshot.txBytes == 0 {
                return false
            }
            if isLoopback(snapshot.key.remote) { return false }
            return true
        }
    }

    private static func isLoopback(_ address: String) -> Bool {
        address.hasPrefix("127.") || address.hasPrefix("::1.") || address == "::1"
    }
}
