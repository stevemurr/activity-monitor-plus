import Foundation
import Synchronization

/// Progress ticks emitted during a scan (throttled, off the main actor).
struct ScanProgress: Sendable {
    var filesScanned: Int
    var bytesScanned: UInt64
}

/// Result of a completed (or cancelled) scan. The tree is already built and
/// pruned; `deniedCount` drives the Full Disk Access prompt.
struct StorageScanResult: Sendable {
    var root: StorageNode
    var scannedBytes: UInt64
    var fileCount: Int
    var deniedCount: Int
    var cancelled: Bool
    var hitFileCap: Bool
}

/// On-demand disk scanner seam. Async because the walk is long-running; the
/// live implementation runs it off the main actor and honors cancellation.
protocol DiskScanning: Sendable {
    func scan(volumeRoot: URL, volumeName: String, usedBytes: UInt64,
              progress: @Sendable @escaping (ScanProgress) -> Void) async -> StorageScanResult
}

/// Cooperative cancel flag shared with the detached walk (Task.detached does not
/// inherit cancellation, so we bridge it explicitly).
private final class CancelFlag: Sendable {
    private let flag = Mutex(false)
    var isCancelled: Bool { flag.withLock { $0 } }
    func cancel() { flag.withLock { $0 = true } }
}

/// Efficient native scanner built on `FileManager.enumerator` — itself a wrapper
/// around the `getattrlistbulk(2)` syscall, so a single prefetch of the size
/// attributes avoids a per-file `stat`. Designed to stay gentle: `.utility`
/// priority, streaming aggregation into a directory-keyed accumulator (memory
/// bounded by folder count), bounded per-directory file detail, and no symlink
/// following or crossing into other volumes.
final class LiveDiskScanner: DiskScanning {
    /// Synthetic / firmlink mount points skipped when scanning `/` so the Data
    /// volume isn't double-counted and external mounts aren't traversed.
    private static let skipPaths: Set<String> = [
        "/Volumes", "/System/Volumes", "/dev", "/net", "/home",
        "/private/var/vm", "/.vol", "/.fseventsd",
    ]

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]

    func scan(volumeRoot: URL, volumeName: String, usedBytes: UInt64,
              progress: @Sendable @escaping (ScanProgress) -> Void) async -> StorageScanResult {
        let cancel = CancelFlag()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .utility) {
                Self.walk(volumeRoot: volumeRoot, volumeName: volumeName,
                          usedBytes: usedBytes, progress: progress,
                          isCancelled: { cancel.isCancelled })
            }.value
        } onCancel: {
            cancel.cancel()
        }
    }

    private static func walk(volumeRoot: URL, volumeName: String, usedBytes: UInt64,
                             progress: @Sendable (ScanProgress) -> Void,
                             isCancelled: () -> Bool) -> StorageScanResult {
        let fm = FileManager.default
        let keySet = Set(resourceKeys)
        let rootPath = volumeRoot.path

        var accumulator = ScanAccumulator()
        accumulator.addDirectory(path: rootPath, parent: nil)

        var denied = 0
        let enumerator = fm.enumerator(
            at: volumeRoot,
            includingPropertiesForKeys: resourceKeys,
            options: [],   // include hidden and package contents, like DaisyDisk
            errorHandler: { _, _ in denied += 1; return true })

        var sinceProgress = 0
        while let item = enumerator?.nextObject() as? URL {
            if isCancelled() { break }

            let path = item.path
            if skipPaths.contains(path) {
                enumerator?.skipDescendants()
                continue
            }

            guard let values = try? item.resourceValues(forKeys: keySet) else {
                denied += 1
                continue
            }
            if values.isSymbolicLink == true { continue }

            let parent = item.deletingLastPathComponent().path
            if values.isDirectory == true {
                accumulator.addDirectory(path: path, parent: parent)
            } else {
                let bytes = UInt64(values.totalFileAllocatedSize
                                   ?? values.fileAllocatedSize
                                   ?? values.fileSize ?? 0)
                accumulator.addFile(parent: parent, name: item.lastPathComponent,
                                    bytes: bytes,
                                    capPerDir: StorageTree.defaultTopFilesPerDir,
                                    globalCap: StorageTree.defaultGlobalFileCap)
            }

            sinceProgress += 1
            if sinceProgress >= 4000 {
                sinceProgress = 0
                progress(ScanProgress(filesScanned: accumulator.fileCount,
                                      bytesScanned: accumulator.scannedBytes))
            }
        }

        accumulator.deniedCount = denied
        let cancelled = isCancelled()
        progress(ScanProgress(filesScanned: accumulator.fileCount,
                              bytesScanned: accumulator.scannedBytes))

        let root = StorageTree.build(rootPath: rootPath, rootName: volumeName,
                                     accumulator: accumulator, usedBytes: usedBytes)
        return StorageScanResult(root: root, scannedBytes: accumulator.scannedBytes,
                                 fileCount: accumulator.fileCount, deniedCount: denied,
                                 cancelled: cancelled, hitFileCap: accumulator.hitFileCap)
    }
}
