import SwiftUI

struct MemoryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(title: "Memory", symbol: "memorychip") {
            if let memory = model.memory {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Format.bytes(memory.usedBytes))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("of \(Format.bytes(memory.totalBytes)) used")
                            .foregroundStyle(.secondary)
                    }
                    UsageBar(segments: [
                        (Color(nsColor: .systemBlue),
                         fraction(memory.appBytes, of: memory)),
                        (Color(nsColor: .systemOrange),
                         fraction(memory.wiredBytes, of: memory)),
                        (Color(nsColor: .systemPurple),
                         fraction(memory.compressedBytes, of: memory)),
                    ])
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                        legendRow(color: Color(nsColor: .systemBlue),
                                  label: "App Memory", bytes: memory.appBytes)
                        legendRow(color: Color(nsColor: .systemOrange),
                                  label: "Wired", bytes: memory.wiredBytes)
                        legendRow(color: Color(nsColor: .systemPurple),
                                  label: "Compressed", bytes: memory.compressedBytes)
                    }
                    .font(.callout)
                }
            } else {
                Text("Memory statistics unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("overview.memoryCard")
    }

    private func fraction(_ bytes: UInt64, of memory: MemorySnapshot) -> Double {
        memory.totalBytes == 0 ? 0 : Double(bytes) / Double(memory.totalBytes)
    }

    private func legendRow(color: Color, label: String, bytes: UInt64) -> some View {
        GridRow {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(label)
            }
            Text(Format.bytes(bytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }
}
