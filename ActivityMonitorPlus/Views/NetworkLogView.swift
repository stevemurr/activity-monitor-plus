import Charts
import SwiftUI

struct NetworkLogView: View {
    @Environment(AppModel.self) private var model
    @State private var collapsedProcesses: Set<NetworkProcessKey> = []
    @State private var filter = ""
    @State private var eventFilter = EventFilter.all

    private enum EventFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case recent = "Recent"
        var id: Self { self }
    }

    private struct ActivitySummary: Identifiable {
        let process: NetworkProcessKey
        let bytesIn: UInt64
        let bytesOut: UInt64
        var id: NetworkProcessKey { process }
    }

    private struct ProtocolSummary: Identifiable {
        let proto: NetProto
        let count: Int
        var id: String { proto.rawValue }
    }

    private var filteredEvents: [ConnectionEvent] {
        model.connectionEvents.filter { event in
            let matchesText = filter.isEmpty
                || event.processName.localizedCaseInsensitiveContains(filter)
                || event.remote.localizedCaseInsensitiveContains(filter)
            guard matchesText else { return false }
            switch eventFilter {
            case .all:
                return true
            case .active:
                return event.kind != .closed
            case .recent:
                return event.timestamp >= model.lastUpdate.addingTimeInterval(-30)
            }
        }
    }

    private var processRows: [NetworkLogRow] {
        NetworkLogRow.groupedByProcess(filteredEvents)
    }

    private var activity: [ActivitySummary] {
        Dictionary(grouping: filteredEvents) {
            NetworkProcessKey(name: $0.processName, pid: $0.pid)
        }
        .map { process, events in
            ActivitySummary(process: process,
                            bytesIn: events.reduce(0) { $0 + $1.bytesIn },
                            bytesOut: events.reduce(0) { $0 + $1.bytesOut })
        }
        .sorted { ($0.bytesIn + $0.bytesOut) > ($1.bytesIn + $1.bytesOut) }
    }

    private var protocols: [ProtocolSummary] {
        Dictionary(grouping: filteredEvents, by: \.proto)
            .map { ProtocolSummary(proto: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(spacing: 16) {
            throughputPanel

            HStack(alignment: .top, spacing: 16) {
                connectionsPanel
                    .frame(maxWidth: .infinity)
                    .layoutPriority(2)
                VStack(spacing: 16) {
                    topActivityPanel
                    protocolsPanel
                }
                .frame(width: 255)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(20)
        .navigationTitle("Network")
        .navigationSubtitle(model.isNetworkLogPaused ? "Paused" : "Live")
        .toolbar {
            ToolbarItem {
                Button {
                    model.isNetworkLogPaused.toggle()
                } label: {
                    Label(model.isNetworkLogPaused ? "Resume" : "Pause",
                          systemImage: model.isNetworkLogPaused ? "play.fill" : "pause.fill")
                }
                .help(model.isNetworkLogPaused
                      ? "Resume the live event log"
                      : "Pause the display (events keep collecting)")
                .accessibilityIdentifier("network.pauseButton")
            }
            ToolbarItem {
                Button {
                    model.clearNetworkLog()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .help("Clear the event log")
                .accessibilityIdentifier("network.clearButton")
            }
        }
    }

    private var throughputPanel: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 26) {
                    rateMetric("Download", rate: model.throughput.bytesInPerSecond,
                               symbol: "arrow.down", color: AMPStyle.blue)
                    Divider().frame(height: 42)
                    rateMetric("Upload", rate: model.throughput.bytesOutPerSecond,
                               symbol: "arrow.up", color: AMPStyle.purple)
                    Divider().frame(height: 42)
                    HStack(spacing: 9) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Connections")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(model.activeConnectionCount))
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    Spacer()
                    StatusPill(title: model.isNetworkLogPaused ? "Paused" : "Live",
                               color: model.isNetworkLogPaused ? AMPStyle.orange : AMPStyle.green)
                }

                throughputChart
                    .frame(height: 145)
            }
        }
    }

    private func rateMetric(_ title: String, rate: Double,
                            symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Format.rate(rate))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var throughputChart: some View {
        if model.throughputHistory.count >= 2 {
            Chart(model.throughputHistory) { point in
                AreaMark(x: .value("Time", point.timestamp),
                         y: .value("Rate", point.bytesInPerSecond))
                    .foregroundStyle(LinearGradient(
                        colors: [AMPStyle.blue.opacity(0.14), .clear],
                        startPoint: .top, endPoint: .bottom))
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
            .accessibilityLabel("Download and upload throughput, last 60 seconds")
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(AMPStyle.blue.opacity(0.06))
                .overlay {
                    Text("Collecting throughput history…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var connectionsPanel: some View {
        DashboardCard {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Connections")
                        .font(.headline)
                    Picker("Filter", selection: $eventFilter) {
                        ForEach(EventFilter.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search", text: $filter)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 9)
                    .frame(width: 180, height: 27)
                    .background(AMPStyle.subtleFill, in: RoundedRectangle(cornerRadius: 7))
                    .overlay { RoundedRectangle(cornerRadius: 7).stroke(AMPStyle.border) }
                }
                .padding(.bottom, 12)
                Divider()
                connectionTable
            }
        }
    }

    private var connectionTable: some View {
        Table(of: NetworkLogRow.self) {
            TableColumn("Process") { row in
                if row.isProcessGroup {
                    HStack(spacing: 7) {
                        ProcessIconView(pid: row.process.pid, size: 22)
                        Text(row.process.name)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 105, ideal: 140)
            TableColumn("PID") { row in
                if row.isProcessGroup {
                    Text(String(row.process.pid))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 42, ideal: 48, max: 58)
            TableColumn("Event") { row in
                if let event = row.event {
                    Label(event.kind.rawValue, systemImage: symbol(for: event.kind))
                        .foregroundStyle(color(for: event.kind))
                } else {
                    Text("\(row.eventCount) events")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 72, ideal: 84, max: 96)
            TableColumn("Remote") { row in
                Text(row.event?.remote ?? "")
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TableColumn("Protocol") { row in
                if let proto = row.event?.proto {
                    Text(proto.rawValue.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AMPStyle.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AMPStyle.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .width(min: 48, ideal: 54, max: 64)
            TableColumn("In") { row in
                Text(row.event.map { Format.bytes($0.bytesIn) } ?? "")
                    .monospacedDigit()
            }
            .width(min: 52, ideal: 62, max: 76)
            TableColumn("Out") { row in
                Text(row.event.map { Format.bytes($0.bytesOut) } ?? "")
                    .monospacedDigit()
            }
            .width(min: 52, ideal: 62, max: 76)
        } rows: {
            ForEach(processRows) { processRow in
                DisclosureTableRow(
                    processRow,
                    isExpanded: expansionBinding(for: processRow.process)
                ) {
                    ForEach(processRow.children ?? []) { eventRow in
                        TableRow(eventRow)
                    }
                }
            }
        }
        .accessibilityIdentifier("network.table")
        .overlay {
            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    "No Network Events Yet",
                    systemImage: "network",
                    description: Text("Connection opens, closes, and traffic will appear here."))
            }
        }
        .frame(minHeight: 330)
    }

    private var topActivityPanel: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                DashboardSectionTitle("Top Activity")
                let top = Array(activity.prefix(4))
                let maximum = max(top.first.map { $0.bytesIn + $0.bytesOut } ?? 1, 1)
                if top.isEmpty {
                    Text("Activity will appear here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ForEach(top) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                ProcessIconView(pid: item.process.pid, size: 20)
                                Text(item.process.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(Format.bytes(item.bytesIn + item.bytesOut))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            ResourceBar(fraction: Double(item.bytesIn + item.bytesOut)
                                        / Double(maximum))
                        }
                    }
                }
            }
        }
    }

    private var protocolsPanel: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                DashboardSectionTitle("Protocols")
                if protocols.isEmpty {
                    Text("No protocol data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 76)
                } else {
                    HStack(spacing: 14) {
                        Chart(protocols) { item in
                            SectorMark(angle: .value("Events", item.count),
                                       innerRadius: .ratio(0.62),
                                       angularInset: 2)
                                .cornerRadius(2)
                                .foregroundStyle(protocolColor(item.proto))
                        }
                        .chartLegend(.hidden)
                        .frame(width: 82, height: 82)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Network protocols")

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(protocols) { item in
                                HStack(spacing: 6) {
                                    Circle().fill(protocolColor(item.proto))
                                        .frame(width: 7, height: 7)
                                    Text(item.proto.rawValue.uppercased())
                                    Spacer()
                                    Text(String(item.count))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    private func symbol(for kind: ConnectionEvent.Kind) -> String {
        switch kind {
        case .opened: "plus.circle.fill"
        case .closed: "xmark.circle.fill"
        case .traffic: "arrow.up.arrow.down.circle.fill"
        }
    }

    private func color(for kind: ConnectionEvent.Kind) -> Color {
        switch kind {
        case .opened: AMPStyle.green
        case .closed: .secondary
        case .traffic: AMPStyle.blue
        }
    }

    private func protocolColor(_ proto: NetProto) -> Color {
        switch proto {
        case .tcp: AMPStyle.blue
        case .udp: AMPStyle.purple
        }
    }

    private func expansionBinding(for process: NetworkProcessKey) -> Binding<Bool> {
        Binding(
            get: { !collapsedProcesses.contains(process) },
            set: { isExpanded in
                if isExpanded {
                    collapsedProcesses.remove(process)
                } else {
                    collapsedProcesses.insert(process)
                }
            })
    }
}
