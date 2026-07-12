import SwiftUI

struct StorageCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(title: "Storage", symbol: "internaldrive") {
            if model.volumes.isEmpty {
                Text("No volumes found")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.volumes) { volume in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(volume.name)
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Text("\(Format.bytes(volume.usedBytes)) of \(Format.bytes(volume.totalBytes)) used")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            UsageBar(segments: [
                                (Color(nsColor: .systemBlue), volume.usedFraction),
                            ])
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("overview.storage.\(volume.name)")
                    }
                }
            }
        }
        .accessibilityIdentifier("overview.storageCard")
    }
}
