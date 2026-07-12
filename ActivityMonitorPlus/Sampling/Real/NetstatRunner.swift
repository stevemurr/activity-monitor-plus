import Foundation

/// Spawns `netstat -anv` for tcp and udp and parses the socket table.
/// Stateless, so trivially Sendable.
final class NetstatRunner: ConnectionSnapshotProviding {
    func snapshot() async -> [ConnectionSnapshot] {
        async let tcp = run(["-anv", "-p", "tcp"])
        async let udp = run(["-anv", "-p", "udp"])
        let outputs = await [tcp, udp]
        return outputs.flatMap { NetstatParser.filterNoise(NetstatParser.parse($0)) }
    }

    private func run(_ arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(returning: "")
                return
            }
            // Drain the pipe off the cooperative pool; reading before waiting
            // avoids the classic full-pipe-buffer deadlock. Process/Pipe are
            // not Sendable but are owned solely by this closure chain.
            nonisolated(unsafe) let ownedProcess = process
            nonisolated(unsafe) let ownedPipe = pipe
            DispatchQueue.global(qos: .utility).async {
                let data = ownedPipe.fileHandleForReading.readDataToEndOfFile()
                ownedProcess.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}
