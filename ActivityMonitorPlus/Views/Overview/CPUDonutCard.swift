import Charts
import SwiftUI

/// Fixed categorical order validated for adjacent-pair CVD separation
/// (blue → orange → purple → green → pink). "Other"/"Idle" stay neutral.
enum SlicePalette {
    static let processColors: [Color] = [
        Color(nsColor: .systemBlue),
        Color(nsColor: .systemOrange),
        Color(nsColor: .systemPurple),
        Color(nsColor: .systemGreen),
        Color(nsColor: .systemPink),
    ]

    static func colors(for slices: [DonutSlice]) -> [(slice: DonutSlice, color: Color)] {
        var processIndex = 0
        return slices.map { slice in
            switch slice.category {
            case .process:
                let color = processColors[processIndex % processColors.count]
                processIndex += 1
                return (slice, color)
            case .other:
                return (slice, Color(nsColor: .systemGray))
            case .idle:
                return (slice, Color(nsColor: .quaternaryLabelColor))
            }
        }
    }
}

struct CPUDonutCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let colored = SlicePalette.colors(for: model.donutSlices)
        Card(title: "CPU", symbol: "cpu") {
            HStack(alignment: .center, spacing: 28) {
                donut(colored)
                legend(colored)
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("overview.cpuCard")
    }

    private func donut(_ colored: [(slice: DonutSlice, color: Color)]) -> some View {
        Group {
            if colored.isEmpty {
                Circle()
                    .stroke(Color(nsColor: .quaternaryLabelColor), lineWidth: 18)
                    .padding(12)
            } else {
                Chart(colored, id: \.slice.id) { entry in
                    SectorMark(angle: .value("Share", entry.slice.fraction),
                               innerRadius: .ratio(0.62),
                               angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(entry.color)
                }
                .chartLegend(.hidden)
                // Collapse the chart's per-slice AX elements: the legend is the
                // accessible representation, and constant AX snapshotting of a
                // redrawing canvas is exactly what UI tests hammer on.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("CPU usage chart, \(Format.percent(model.cpu.totalUsedFraction)) in use")
            }
        }
        .frame(width: 170, height: 170)
        // Identifier goes on the chart before the overlay so the overlay's
        // texts keep their own identifiers.
        .accessibilityIdentifier("overview.cpuDonut")
        .overlay {
            VStack(spacing: 0) {
                Text(Format.percent(model.cpu.totalUsedFraction))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("overview.cpuTotalLabel")
                Text("CPU")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ colored: [(slice: DonutSlice, color: Color)]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(colored, id: \.slice.id) { entry in
                HStack(spacing: 8) {
                    Circle()
                        .fill(entry.color)
                        .frame(width: 9, height: 9)
                    Text(entry.slice.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(Format.percent(entry.slice.fraction))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("overview.cpuLegend.\(entry.slice.label)")
            }
            Divider()
                .frame(maxWidth: 260)
            // Activity-Monitor-style host split; also explains a large "Other"
            // (root-owned load can't be attributed per-process without root).
            Text("User \(Format.percent(model.cpu.userFraction))  ·  System \(Format.percent(model.cpu.systemFraction))  ·  Idle \(Format.percent(model.cpu.idleFraction))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("overview.cpuSplit")
        }
        .frame(maxWidth: 280)
    }
}
