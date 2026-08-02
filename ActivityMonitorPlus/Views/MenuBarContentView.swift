import Charts
import SwiftUI

struct MenuBarLabel: View {
    var body: some View {
        Image(systemName: "gauge.with.dots.needle.67percent")
    }
}

struct MenuBarContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var topProcesses: [ProcessSample] {
        Array(model.cpu.processes
            .filter { $0.cpuFraction != nil }
            .sorted { ($0.cpuFraction ?? 0) > ($1.cpuFraction ?? 0) }
            .prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            systemLoad
            HStack(alignment: .top, spacing: 10) {
                memoryTile
                networkTile
            }
            topProcessesPanel
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 390)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            Text("Activity Monitor Plus")
                .font(.headline)
            Spacer()
            StatusPill(title: model.isNetworkLogPaused ? "Paused" : "Live",
                       color: model.isNetworkLogPaused ? AMPStyle.orange : AMPStyle.green)
        }
    }

    private var systemLoad: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("System Load")
                            .font(.headline)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(Format.percent(model.cpu.totalUsedFraction))
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .foregroundStyle(AMPStyle.blue)
                                .monospacedDigit()
                            Text("CPU")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    StatusPill(title: loadStatus,
                               color: model.cpu.totalUsedFraction < 0.8
                                   ? AMPStyle.green : AMPStyle.orange)
                }

                cpuChart
                    .frame(height: 74)

                Text("User \(Format.percent(model.cpu.userFraction))  ·  System \(Format.percent(model.cpu.systemFraction))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var loadStatus: String {
        model.cpu.totalUsedFraction < 0.8 ? "Normal" : "Elevated"
    }

    @ViewBuilder
    private var cpuChart: some View {
        if model.systemHistory.count >= 2 {
            Chart(model.systemHistory) { point in
                AreaMark(x: .value("Time", point.timestamp),
                         y: .value("CPU", point.cpuUsedFraction))
                    .foregroundStyle(LinearGradient(
                        colors: [AMPStyle.blue.opacity(0.2), .clear],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.timestamp),
                         y: .value("CPU", point.cpuUsedFraction))
                    .foregroundStyle(AMPStyle.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("CPU usage history")
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(AMPStyle.blue.opacity(0.06))
        }
    }

    private var memoryTile: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Memory")
                .font(.subheadline.weight(.semibold))
            if let memory = model.memory {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Format.bytes(memory.usedBytes))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text("/ \(Format.bytes(memory.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                UsageBar(segments: [
                    (AMPStyle.blue, fraction(memory.appBytes, memory.totalBytes)),
                    (AMPStyle.orange, fraction(memory.wiredBytes, memory.totalBytes)),
                    (AMPStyle.purple, fraction(memory.compressedBytes, memory.totalBytes)),
                ], height: 7)
            } else {
                Text("Unavailable").foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(AMPStyle.cardFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AMPStyle.border) }
    }

    private var networkTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 14) {
                miniRate("Download", model.throughput.bytesInPerSecond, AMPStyle.blue)
                miniRate("Upload", model.throughput.bytesOutPerSecond, AMPStyle.purple)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(AMPStyle.cardFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AMPStyle.border) }
    }

    private func miniRate(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Format.rate(value))
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var topProcessesPanel: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Top Processes")
                    .font(.headline)
                let maxCPU = max(topProcesses.first?.cpuFraction ?? 0.01, 0.01)
                ForEach(topProcesses) { process in
                    HStack(spacing: 8) {
                        ProcessIconView(pid: process.pid, size: 23)
                        Text(process.name)
                            .font(.callout)
                            .lineLimit(1)
                            .frame(width: 105, alignment: .leading)
                        ResourceBar(fraction: (process.cpuFraction ?? 0) / maxCPU)
                        Text(process.cpuFraction.map(Format.percent) ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 9) {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Open Activity Monitor Plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("menubar.open")

            HStack(spacing: 10) {
                Button {
                    model.isNetworkLogPaused.toggle()
                } label: {
                    Label(model.isNetworkLogPaused ? "Resume" : "Pause",
                          systemImage: model.isNetworkLogPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
            }

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("menubar.quit")
        }
    }

    private func fraction(_ value: UInt64, _ total: UInt64) -> Double {
        total == 0 ? 0 : Double(value) / Double(total)
    }
}
