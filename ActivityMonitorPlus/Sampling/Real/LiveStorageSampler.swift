import Foundation

final class LiveStorageSampler: StorageSampling {
    func sample() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsBrowsableKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]) else { return [] }

        var volumes: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable == true,
                  let total = values.volumeTotalCapacity, total > 0 else { continue }
            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            volumes.append(VolumeInfo(path: url.path,
                                      name: values.volumeName ?? url.lastPathComponent,
                                      totalBytes: UInt64(total),
                                      availableBytes: UInt64(max(0, available))))
        }
        return volumes.sorted { $0.path < $1.path }
    }
}
