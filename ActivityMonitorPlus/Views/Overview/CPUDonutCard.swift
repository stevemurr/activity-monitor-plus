import Charts
import SwiftUI

/// Kept under its original type name so existing accessibility and screenshot
/// coverage continue to follow the CPU surface after the redesign.
struct CPUDonutCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.navigateSidebar) private var navigateSidebar

    private var topProcesses: [ProcessSample] { model.topProcesses }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                DashboardSectionTitle("System Load") {
                    Text("60 seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AMPStyle.subtleFill, in: Capsule())
                }
                .accessibilityIdentifier("overview.cpuCard")

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Format.percent(model.cpu.totalUsedFraction))
                                .font(.system(size: 35, weight: .semibold, design: .rounded))
                                .foregroundStyle(AMPStyle.blue)
                                .monospacedDigit()
                                .accessibilityIdentifier("overview.cpuTotalLabel")
                            Text("CPU")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        splitRow("User", model.cpu.userFraction, AMPStyle.blue)
                        splitRow("System", model.cpu.systemFraction, AMPStyle.orange)
                        splitRow("Idle", model.cpu.idleFraction, .secondary)
                    }
                    .frame(width: 118, alignment: .leading)

                    cpuHistoryChart
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 142)

                Divider()

                DashboardSectionTitle("Top Processes") {
                    Button("View Processes") { navigateSidebar(.processes) }
                        .buttonStyle(.link)
                        .font(.caption)
                }

                VStack(spacing: 8) {
                    let processes = topProcesses
                    let maxCPU = max(processes.first?.cpuFraction ?? 0.01, 0.01)
                    ForEach(processes) { process in
                        processRow(process, maxCPU: maxCPU)
                    }
                }
            }
        }
        .frame(minHeight: 368)
    }

    private func splitRow(_ title: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Format.percent(value))
                .monospacedDigit()
        }
        .font(.caption)
    }

    @ViewBuilder
    private var cpuHistoryChart: some View {
        if model.systemHistory.count >= 2 {
            Chart(model.systemHistory) { point in
                AreaMark(x: .value("Time", point.timestamp),
                         y: .value("CPU", point.cpuUsedFraction))
                    .foregroundStyle(LinearGradient(
                        colors: [AMPStyle.blue.opacity(0.2), AMPStyle.blue.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.timestamp),
                         y: .value("CPU", point.cpuUsedFraction))
                    .foregroundStyle(AMPStyle.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                    AxisGridLine().foregroundStyle(AMPStyle.border)
                    AxisValueLabel {
                        if let fraction = value.as(Double.self) {
                            Text(Format.percent(fraction))
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("CPU usage history, \(Format.percent(model.cpu.totalUsedFraction)) in use")
            .accessibilityIdentifier("overview.cpuDonut")
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(AMPStyle.blue.opacity(0.06))
                .overlay {
                    Text("Collecting history…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("overview.cpuDonut")
        }
    }

    private func processRow(_ process: ProcessSample, maxCPU: Double) -> some View {
        HStack(spacing: 9) {
            ProcessIconView(pid: process.pid, size: 22)
            Text(process.name)
                .font(.callout)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
            ResourceBar(fraction: (process.cpuFraction ?? 0) / maxCPU)
            Text(process.cpuFraction.map(Format.percent) ?? "—")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overview.cpuLegend.\(process.name)")
    }
}
