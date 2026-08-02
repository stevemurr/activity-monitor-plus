import Foundation

/// Spawns protocol-filtered `netstat -anv` commands and parses the socket list.
///
/// Both commands run sequentially on a private queue: `Foundation.Process`
/// races when instances launch concurrently, which can corrupt output or
/// deadlock. Filtering at the command keeps each sample small by excluding the
/// unrelated UNIX, routing, and kernel-control tables emitted by bare `-anv`.
/// A watchdog terminates a stuck command so it cannot freeze the sampling loop.
final class NetstatRunner: ConnectionSnapshotProviding {
    private let queue = DispatchQueue(label: "com.stevemurr.ActivityMonitorPlus.netstat")

    func snapshot() async -> [ConnectionSnapshot] {
        await withCheckedContinuation { continuation in
            queue.async {
                let snapshots = ["tcp", "udp"].flatMap { proto in
                    let output = Self.runOnce(arguments: ["-anv", "-p", proto])
                    return NetstatParser.parse(output)
                }
                let filtered = NetstatParser.filterNoise(snapshots)
                continuation.resume(returning: filtered.isEmpty
                    ? LibprocSocketSnapshotter.snapshot()
                    : filtered)
            }
        }
    }

    private static func runOnce(arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        // Never let a stuck netstat block the sampler indefinitely.
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4, execute: watchdog)
        // Read to EOF before reaping — the canonical no-deadlock ordering.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return String(decoding: data, as: UTF8.self)
    }
}
