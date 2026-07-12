import SwiftUI

struct ProcessRow: Identifiable {
    let pid: Int32
    let name: String
    let cpuFraction: Double?
    let residentBytes: UInt64?
    var id: Int32 { pid }
    // Unreadable (nil) values sort below every real value.
    var cpuSortKey: Double { cpuFraction ?? -1 }
    var memorySortKey: Double { residentBytes.map(Double.init) ?? -1 }
}

struct ProcessTableView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\ProcessRow.cpuSortKey,
                                                      order: .reverse)]
    @State private var filter = ""

    private var rows: [ProcessRow] {
        var rows = model.cpu.processes.map {
            ProcessRow(pid: $0.pid, name: $0.name,
                       cpuFraction: $0.cpuFraction, residentBytes: $0.residentBytes)
        }
        if !filter.isEmpty {
            rows = rows.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        }
        return rows.sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, sortOrder: $sortOrder) {
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
        .accessibilityIdentifier("processes.table")
        .searchable(text: $filter, placement: .toolbar, prompt: "Filter processes")
        .navigationTitle("Processes")
        .navigationSubtitle("\(rows.count) processes")
        .toolbar {
            ToolbarItem {
                // Stable sorting control (Table header AX can be flaky in XCUITest).
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
