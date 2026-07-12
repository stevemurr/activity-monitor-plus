import Foundation

/// Spawns `netstat -anv` (all protocols in one table) and parses the socket
/// list.
///
/// Serialized on a private queue: `Foundation.Process` races when several
/// instances are launched concurrently, which both corrupts output and can
/// deadlock. A watchdog terminates a stuck netstat so a single hung spawn can
/// never freeze the sampling loop.
final class NetstatRunner: ConnectionSnapshotProviding {
    private let queue = DispatchQueue(label: "com.stevemurr.ActivityMonitorPlus.netstat")

    func snapshot() async -> [ConnectionSnapshot] {
        let output = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            queue.async { continuation.resume(returning: Self.runOnce()) }
        }
        return NetstatParser.filterNoise(NetstatParser.parse(output))
    }

    private static func runOnce() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-anv"]
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
