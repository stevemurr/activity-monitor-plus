import SwiftUI

struct StorageCard: View {
    @Environment(AppModel.self) private var model
    @State private var breakdownVolume: VolumeInfo?

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                DashboardSectionTitle("Storage")
                    .accessibilityIdentifier("overview.storageCard")

                if model.volumes.isEmpty {
                    ContentUnavailableView("No Volumes Found",
                                           systemImage: "internaldrive")
                } else {
                    ForEach(Array(model.volumes.prefix(2))) { volume in
                        Button {
                            breakdownVolume = volume
                        } label: {
                            volumeRow(volume)
                        }
                        .buttonStyle(.plain)
                        .help("Analyze what's using space on \(volume.name)")
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("overview.storage.\(volume.name)")

                        if volume.id != model.volumes.prefix(2).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minHeight: 246)
        .sheet(item: $breakdownVolume) { volume in
            StorageBreakdownView(volume: volume)
                .environment(model)
        }
    }

    private func volumeRow(_ volume: VolumeInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(volume.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(Format.bytes(volume.usedBytes)) of \(Format.bytes(volume.totalBytes)) used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            UsageBar(segments: [(AMPStyle.blue, volume.usedFraction)], height: 8)

            Text("\(Format.bytes(volume.availableBytes)) available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}
