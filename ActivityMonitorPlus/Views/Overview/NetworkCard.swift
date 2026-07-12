import Charts
import SwiftUI

struct NetworkCard: View {
    @Environment(AppModel.self) private var model

    private let inColor = Color(nsColor: .systemBlue)
    private let outColor = Color(nsColor: .systemOrange)

    var body: some View {
        Card(title: "Network", symbol: "network") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 20) {
                    rateLabel(symbol: "arrow.down", color: inColor, name: "In",
                              rate: model.throughput.bytesInPerSecond)
                    rateLabel(symbol: "arrow.up", color: outColor, name: "Out",
                              rate: model.throughput.bytesOutPerSecond)
                }
                sparkline
            }
        }
        .accessibilityIdentifier("overview.networkCard")
    }

    private func rateLabel(symbol: String, color: Color, name: String,
                           rate: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.bold())
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(Format.rate(rate))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overview.network\(name)Rate")
    }

    @ViewBuilder
    private var sparkline: some View {
        if model.throughputHistory.count >= 2 {
            Chart(model.throughputHistory) { point in
                LineMark(x: .value("Time", point.timestamp),
                         y: .value("Rate", point.bytesInPerSecond),
                         series: .value("Direction", "In"))
                    .foregroundStyle(inColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                LineMark(x: .value("Time", point.timestamp),
                         y: .value("Rate", point.bytesOutPerSecond),
                         series: .value("Direction", "Out"))
                    .foregroundStyle(outColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden) // sparkline; values live in the rate readouts
            .chartLegend(.hidden) // identity carried by the labeled readouts above
            // Collapse per-bin AX elements — see CPUDonutCard.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Network throughput, last 60 seconds")
            .frame(height: 70)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
                .frame(height: 70)
        }
    }
}
