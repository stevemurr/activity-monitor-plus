import SwiftUI

struct ProcessTableView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\ProcessRow.cpuSortKey,
                                                      order: .reverse)]
    @State private var filter = ""
    @State private var scope = ProcessScope.all
    @State private var selection = Set<Int32>()
    @State private var ranker = StableRanker()
    @State private var displayed: [ProcessRow] = []
    @State private var totalCount = 0
    @State private var matchCount = 0
    @State private var showQuitDialog = false
    @State private var killErrors: [String] = []
    @State private var inspected: InspectTarget?

    /// Bounds AppKit's eager table-row realization cost while leaving the full
    /// process set available to search and scope filters.
    private static let displayLimit = 150

    private struct InspectTarget: Identifiable {
        let row: ProcessRow
        let details: ProcessDetails
        let events: [ConnectionEvent]
        var id: Int32 { row.pid }
    }

    private enum ProcessScope: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case highCPU = "High CPU"
        var id: Self { self }
    }

    private var selectedRows: [ProcessRow] {
        displayed.filter { selection.contains($0.pid) }
    }

    /// Ranked once per tick on the model. Building `ProcessRow`s for all ~1000
    /// samples here ran twice per body pass, once for each tile field.
    private var topProcess: ProcessSample? { model.topProcesses.first }

    var body: some View {
        VStack(spacing: 16) {
            summaryTiles

            DashboardCard {
                VStack(spacing: 0) {
                    controls
                        .padding(.bottom, 12)
                    Divider()
                    HStack(spacing: 0) {
                        processTable
                        if let selected = selectedRows.first {
                            Divider()
                            selectionInspector(selected)
                                .frame(width: 235)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(20)
        .navigationTitle("Processes")
        .navigationSubtitle(subtitle)
        .onAppear { refreshRows(force: true) }
        .onChange(of: model.lastUpdate) { refreshRows() }
        .onChange(of: sortOrder) { refreshRows(force: true) }
        .onChange(of: filter) { refreshRows() }
        .onChange(of: scope) { refreshRows(force: true) }
        .confirmationDialog(quitDialogTitle, isPresented: $showQuitDialog) {
            Button("Quit", role: .destructive) { performKill(force: false) }
            Button("Force Quit", role: .destructive) { performKill(force: true) }
        } message: {
            Text("Quit sends the process a termination request; Force Quit ends it immediately and may lose unsaved data.")
        }
        .alert("Some processes could not be quit", isPresented: .init(
            get: { !killErrors.isEmpty },
            set: { if !$0 { killErrors = [] } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(killErrors.joined(separator: "\n"))
        }
        .sheet(item: $inspected) { target in
            ProcessInspectView(row: target.row, details: target.details,
                               events: target.events)
        }
    }

    private var summaryTiles: some View {
        HStack(spacing: 14) {
            MetricTile(title: "CPU Load",
                       value: Format.percent(model.cpu.totalUsedFraction),
                       detail: "across \(model.cpu.coreCount) cores",
                       color: AMPStyle.blue,
                       progress: model.cpu.totalUsedFraction,
                       symbol: "cpu")
            MetricTile(title: "Memory Used",
                       value: model.memory.map { Format.bytes($0.usedBytes) } ?? "—",
                       detail: model.memory.map { "of \(Format.bytes($0.totalBytes))" },
                       color: AMPStyle.purple,
                       progress: model.memory?.usedFraction,
                       symbol: "memorychip")
            let top = topProcess
            MetricTile(title: "Top Process",
                       value: top?.name ?? "—",
                       detail: top?.cpuFraction.map(Format.percent),
                       color: AMPStyle.blue,
                       symbol: "chart.bar.fill")
        }
        .frame(height: 104)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Scope", selection: $scope) {
                ForEach(ProcessScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter processes", text: $filter)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(width: 220, height: 28)
            .background(AMPStyle.subtleFill, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).stroke(AMPStyle.border)
            }

            Picker("Sort", selection: sortSelection) {
                Text("Highest CPU").tag(SortChoice.cpuDescending)
                Text("Lowest CPU").tag(SortChoice.cpuAscending)
                Text("Name").tag(SortChoice.name)
                Text("Memory").tag(SortChoice.memory)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("processes.sortPicker")

            Button {
                inspectFirstSelected()
            } label: {
                Label("Inspect", systemImage: "info.circle")
            }
            .disabled(selection.isEmpty)
            .help("Show details for the selected process")
            .accessibilityIdentifier("processes.inspectButton")

            Button {
                showQuitDialog = true
            } label: {
                Label("Quit Process", systemImage: "xmark.octagon")
            }
            .disabled(selection.isEmpty)
            .help("Quit or force-quit the selected processes")
            .accessibilityIdentifier("processes.quitButton")
        }
        .labelStyle(.iconOnly)
    }

    private var processTable: some View {
        Table(displayed, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Process", value: \ProcessRow.name) { row in
                HStack(spacing: 8) {
                    ProcessIconView(pid: row.pid, size: 24)
                    Text(row.name).lineLimit(1)
                }
            }
            TableColumn("Status") { _ in
                HStack(spacing: 6) {
                    Circle().fill(AMPStyle.green).frame(width: 7, height: 7)
                    Text("Running")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 70, ideal: 82, max: 95)
            TableColumn("PID", value: \ProcessRow.pid) { row in
                Text(String(row.pid))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 48, ideal: 54, max: 66)
            TableColumn("CPU", value: \ProcessRow.cpuSortKey) { row in
                HStack(spacing: 7) {
                    Text(row.cpuFraction.map(Format.percent) ?? "—")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                    ResourceBar(fraction: row.cpuFraction ?? 0)
                }
            }
            .width(min: 85, ideal: 105, max: 125)
            TableColumn("Memory", value: \ProcessRow.memorySortKey) { row in
                Text(row.residentBytes.map(Format.bytes) ?? "—")
                    .monospacedDigit()
            }
            .width(min: 72, ideal: 82, max: 100)
            TableColumn("Energy") { row in
                energyIndicator(row.cpuFraction)
            }
            .width(min: 48, ideal: 54, max: 64)
        }
        .contextMenu(forSelectionType: Int32.self) { pids in
            if !pids.isEmpty {
                Button("Inspect") {
                    selection = pids
                    inspectFirstSelected()
                }
                Divider()
                Button("Quit…", role: .destructive) {
                    selection = pids
                    showQuitDialog = true
                }
            }
        } primaryAction: { pids in
            selection = pids
            inspectFirstSelected()
        }
        .accessibilityIdentifier("processes.table")
        .frame(minHeight: 410)
    }

    private func energyIndicator(_ cpu: Double?) -> some View {
        let value = cpu ?? 0
        return HStack(spacing: 2) {
            ForEach(0..<(value > 0.1 ? 2 : value > 0.01 ? 1 : 0), id: \.self) { _ in
                Image(systemName: "bolt.fill")
                    .foregroundStyle(AMPStyle.orange)
            }
            if value <= 0.01 {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func selectionInspector(_ row: ProcessRow) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                ProcessIconView(pid: row.pid, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("PID \(row.pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Divider()
            inspectorMetric("CPU", row.cpuFraction.map(Format.percent) ?? "Unavailable",
                            fraction: row.cpuFraction, color: AMPStyle.blue)
            inspectorMetric("Memory", row.residentBytes.map(Format.bytes) ?? "Unavailable",
                            fraction: memoryFraction(row), color: AMPStyle.purple)

            HStack {
                Text("Network Events")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(model.recentEvents(forPid: row.pid).count))
                    .monospacedDigit()
            }
            .font(.caption)

            Spacer()

            Button("Inspect Details") { inspectFirstSelected() }
                .frame(maxWidth: .infinity)
            Button("Quit…", role: .destructive) { showQuitDialog = true }
                .frame(maxWidth: .infinity)
        }
        .padding(.leading, 16)
        .padding(.vertical, 14)
    }

    private func inspectorMetric(_ title: String, _ value: String,
                                 fraction: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(value).monospacedDigit()
            }
            .font(.caption)
            ResourceBar(fraction: fraction ?? 0, color: color)
        }
    }

    private func memoryFraction(_ row: ProcessRow) -> Double? {
        guard let bytes = row.residentBytes,
              let total = model.memory?.totalBytes, total > 0 else { return nil }
        return Double(bytes) / Double(total)
    }

    private var subtitle: String {
        if !filter.isEmpty || scope != .all {
            let shown = min(matchCount, Self.displayLimit)
            return matchCount > Self.displayLimit
                ? "\(shown) of \(matchCount) matches"
                : "\(matchCount) \(matchCount == 1 ? "match" : "matches")"
        }
        return totalCount > Self.displayLimit
            ? "Top \(Self.displayLimit) of \(totalCount) running"
            : "\(totalCount) running"
    }

    private var quitDialogTitle: String {
        let names = selectedRows.map(\.name)
        switch names.count {
        case 0: return "Quit process?"
        case 1: return "Quit “\(names[0])”?"
        default: return "Quit \(names.count) processes?"
        }
    }

    private func refreshRows(force: Bool = false) {
        let all = model.cpu.processes.map(ProcessRow.init)
        let ordered = ranker.orderedRows(all, sortedBy: sortOrder, now: Date(),
                                         forceRerank: force)
        let scoped = ordered.filter { row in
            switch scope {
            case .all: true
            case .active: (row.cpuFraction ?? 0) > 0.001
            case .highCPU: (row.cpuFraction ?? 0) >= 0.05
            }
        }
        let matches = filter.isEmpty
            ? scoped
            : scoped.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        totalCount = all.count
        matchCount = matches.count
        displayed = Array(matches.prefix(Self.displayLimit))
        selection = selection.intersection(Set(all.map(\.pid)))
    }

    private func performKill(force: Bool) {
        let targets = selectedRows.map { (pid: $0.pid, name: $0.name) }
        killErrors = model.terminate(pids: targets, force: force)
    }

    private func inspectFirstSelected() {
        guard let row = selectedRows.first else { return }
        inspected = InspectTarget(row: row,
                                  details: model.details(pid: row.pid, name: row.name),
                                  events: model.recentEvents(forPid: row.pid))
    }

    private enum SortChoice: Hashable {
        case cpuDescending, cpuAscending, name, memory, custom
    }

    private var sortSelection: Binding<SortChoice> {
        Binding {
            guard let first = sortOrder.first else { return .custom }
            switch (first.keyPath, first.order) {
            case (\ProcessRow.cpuSortKey, .reverse): return .cpuDescending
            case (\ProcessRow.cpuSortKey, .forward): return .cpuAscending
            case (\ProcessRow.name, _): return .name
            case (\ProcessRow.memorySortKey, _): return .memory
            default: return .custom
            }
        } set: { choice in
            switch choice {
            case .cpuDescending:
                sortOrder = [KeyPathComparator(\ProcessRow.cpuSortKey, order: .reverse)]
            case .cpuAscending:
                sortOrder = [KeyPathComparator(\ProcessRow.cpuSortKey, order: .forward)]
            case .name:
                sortOrder = [KeyPathComparator(\ProcessRow.name, order: .forward)]
            case .memory:
                sortOrder = [KeyPathComparator(\ProcessRow.memorySortKey, order: .reverse)]
            case .custom:
                break
            }
        }
    }
}
