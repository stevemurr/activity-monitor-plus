import Darwin
import Foundation

final class LiveMemorySampler: MemorySampling {
    private let host = mach_host_self()
    private let pageSize: UInt64

    init() {
        var size: vm_size_t = 0
        pageSize = host_page_size(mach_host_self(), &size) == KERN_SUCCESS
            ? UInt64(size) : 16384
    }

    func sample() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        // "App memory" in Activity Monitor terms: anonymous pages minus purgeable.
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0

        return MemorySnapshot(
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            appBytes: appPages * pageSize,
            wiredBytes: UInt64(stats.wire_count) * pageSize,
            compressedBytes: UInt64(stats.compressor_page_count) * pageSize)
    }
}
