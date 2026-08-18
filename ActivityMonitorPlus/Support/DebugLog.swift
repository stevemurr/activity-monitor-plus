import Foundation

/// Appends a line to the file named by the AMP_DEBUG env var (no-op if unset).
/// Temporary instrumentation helper.
enum DebugLog {
    private static let path = ProcessInfo.processInfo.environment["AMP_DEBUG"]

    /// `@autoclosure` so callers on the 1 Hz path don't build an interpolated
    /// string on every tick just to throw it away when logging is off.
    static func write(_ message: @autoclosure () -> String) {
        guard let path else { return }
        let line = "AMP_DEBUG \(message())\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            FileHandle.standardError.write(Data(line.utf8))
        }
    }
}
