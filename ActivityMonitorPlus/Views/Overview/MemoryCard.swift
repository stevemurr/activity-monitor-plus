import Charts
import SwiftUI

struct MemoryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                DashboardSectionTitle("Memory")
                    .accessibilityIdentifier("overview.memoryCard")

                if let memory = model.memory {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Format.bytes(memory.usedBytes))
                            .font(.system(size: 27, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("of \(Format.bytes(memory.totalBytes))")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 7) {
                        Text("Memory Pressure")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        StatusPill(title: pressureTitle(memory), color: pressureColor(memory))
                    }

                    UsageBar(segments: [
                        (AMPStyle.blue, fraction(memory.appBytes, of: memory)),
                        (AMPStyle.orange, fraction(memory.wiredBytes, of: memory)),
                        (AMPStyle.purple, fraction(memory.compressedBytes, of: memory)),
                    ], height: 10)

                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 7) {
                        legendRow(color: AMPStyle.blue, label: "App Memory", bytes: memory.appBytes)
                        legendRow(color: AMPStyle.orange, label: "Wired", bytes: memory.wiredBytes)
                        legendRow(color: AMPStyle.purple, label: "Compressed", bytes: memory.compressedBytes)
                    }
                    .font(.caption)

                    Divider()
                    Text("Memory Usage · 60 seconds")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    memoryChart(total: memory.totalBytes)
                        .frame(height: 82)
                } else {
                    ContentUnavailableView("Memory Unavailable",
                                           systemImage: "memorychip")
                }
            }
        }
        .frame(minHeight: 368)
    }

    private func fraction(_ bytes: UInt64, of memory: MemorySnapshot) -> Double {
        memory.totalBytes == 0 ? 0 : Double(bytes) / Double(memory.totalBytes)
    }

    private func pressureTitle(_ memory: MemorySnapshot) -> String {
        if memory.usedFraction < 0.75 { return "Normal" }
        if memory.usedFraction < 0.9 { return "Elevated" }
        return "High"
    }

    private func pressureColor(_ memory: MemorySnapshot) -> Color {
        if memory.usedFraction < 0.75 { return AMPStyle.green }
        if memory.usedFraction < 0.9 { return AMPStyle.orange }
        return AMPStyle.red
    }

    private func legendRow(color: Color, label: String, bytes: UInt64) -> some View {
        GridRow {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
            Spacer()
            Text(Format.bytes(bytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func memoryChart(total: UInt64) -> some View {
        let points = model.systemHistory.filter { $0.memoryUsedBytes != nil }
        if points.count >= 2 {
            Chart(points) { point in
                AreaMark(x: .value("Time", point.timestamp),
                         y: .value("Memory", point.memoryUsedBytes ?? 0))
                    .foregroundStyle(LinearGradient(
                        colors: [AMPStyle.purple.opacity(0.2), AMPStyle.purple.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.timestamp),
                         y: .value("Memory", point.memoryUsedBytes ?? 0))
                    .foregroundStyle(AMPStyle.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...max(total, 1))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Memory usage history")
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(AMPStyle.purple.opacity(0.06))
        }
    }
}
