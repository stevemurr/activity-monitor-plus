import SwiftUI

struct ProcessTableView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\ProcessRow.cpuSortKey,
                                                      order: .reverse)]
    @State private var filter = ""
    @State private var selection = Set<Int32>()
    @State private var ranker = StableRanker()
    @State private var displayed: [ProcessRow] = []
    @State private var totalCount = 0
    @State private var matchCount = 0
    @State private var showQuitDialog = false
    @State private var killErrors: [String] = []

    /// SwiftUI's Table uses automatic row heights, which forces AppKit to
    /// realize an NSHostingView for every row (not just visible ones) on any
    /// reorder/filter — O(rows) synchronous main-thread work. Capping the
    /// rendered rows bounds that cost; the full set is still searchable.
    private static let displayLimit = 150
    @State private var inspected: InspectTarget?

    private struct InspectTarget: Identifiable {
        let row: ProcessRow
        let details: ProcessDetails
        let events: [ConnectionEvent]
        var id: Int32 { row.pid }
    }

    private var selectedRows: [ProcessRow] {
        displayed.filter { selection.contains($0.pid) }
    }

    var body: some View {
        Table(displayed, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Process", value: \.name) { row in
                Text(row.name)
            }
            TableColumn("PID", value: \.pid) { row in
                Text(String(row.pid))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60, max: 80)
            TableColumn("% CPU", value: \.cpuSortKey) { row in
                Text(row.cpuFraction.map { Format.percent($0) } ?? "—")
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 70, max: 90)
            TableColumn("Memory", value: \.memorySortKey) { row in
                Text(row.residentBytes.map(Format.bytes) ?? "—")
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90, max: 120)
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
        .searchable(text: $filter, placement: .toolbar, prompt: "Filter processes")
        .navigationTitle("Processes")
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
        .onAppear { refreshRows(force: true) }
        .onChange(of: model.lastUpdate) { refreshRows() }
        .onChange(of: sortOrder) { refreshRows(force: true) }
        .onChange(of: filter) { refreshRows() }
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                inspectFirstSelected()
            } label: {
                Label("Inspect", systemImage: "info.circle")
            }
            .disabled(selection.isEmpty)
            .help("Show details for the selected process")
            .accessibilityIdentifier("processes.inspectButton")
        }
        ToolbarItem {
            Button {
                showQuitDialog = true
            } label: {
                Label("Quit Process", systemImage: "xmark.octagon")
            }
            .disabled(selection.isEmpty)
            .help("Quit or force-quit the selected processes")
            .accessibilityIdentifier("processes.quitButton")
        }
        ToolbarItem {
            Picker("Sort", selection: sortSelection) {
                Text("Highest CPU").tag(SortChoice.cpuDescending)
                Text("Lowest CPU").tag(SortChoice.cpuAscending)
                Text("Name").tag(SortChoice.name)
                Text("Memory").tag(SortChoice.memory)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("processes.sortPicker")
        }
    }

    private var subtitle: String {
        if !filter.isEmpty {
            let shown = min(matchCount, Self.displayLimit)
            return matchCount > Self.displayLimit
                ? "\(shown) of \(matchCount) matches"
                : "\(matchCount) \(matchCount == 1 ? "match" : "matches")"
        }
        return totalCount > Self.displayLimit
            ? "Top \(Self.displayLimit) of \(totalCount) processes"
            : "\(totalCount) processes"
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
        let matches = filter.isEmpty
            ? ordered
            : ordered.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        totalCount = all.count
        matchCount = matches.count
        displayed = Array(matches.prefix(Self.displayLimit))
        // Drop selection entries for processes that no longer exist.
        let livePids = Set(all.map(\.pid))
        selection = selection.intersection(livePids)
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
