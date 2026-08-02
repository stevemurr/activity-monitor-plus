import Charts
import SwiftUI

struct NetworkCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.navigateSidebar) private var navigateSidebar

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                DashboardSectionTitle("Network") {
                    Button("View Network") { navigateSidebar(.network) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .accessibilityIdentifier("overview.networkCard")

                HStack(spacing: 24) {
                    rateMetric(symbol: "arrow.down", color: AMPStyle.blue,
                               title: "Download", value: model.throughput.bytesInPerSecond)
                    Divider().frame(height: 40)
                    rateMetric(symbol: "arrow.up", color: AMPStyle.purple,
                               title: "Upload", value: model.throughput.bytesOutPerSecond)
                    Divider().frame(height: 40)
                    HStack(spacing: 9) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(model.activeConnectionCount))
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                            Text("active connections")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                throughputChart
                    .frame(height: 118)
            }
        }
        .frame(minHeight: 246)
    }

    private func rateMetric(symbol: String, color: Color,
                            title: String, value: Double) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Format.rate(value))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overview.network\(title == "Download" ? "In" : "Out")Rate")
    }

    @ViewBuilder
    private var throughputChart: some View {
        if model.throughputHistory.count >= 2 {
            Chart(model.throughputHistory) { point in
                LineMark(x: .value("Time", point.timestamp),
                         y: .value("Rate", point.bytesInPerSecond),
                         series: .value("Direction", "Download"))
                    .foregroundStyle(AMPStyle.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", point.timestamp),
                         y: .value("Rate", point.bytesOutPerSecond),
                         series: .value("Direction", "Upload"))
                    .foregroundStyle(AMPStyle.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(AMPStyle.border)
                }
            }
            .chartLegend(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Network throughput, last 60 seconds")
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(AMPStyle.blue.opacity(0.06))
        }
    }
}
