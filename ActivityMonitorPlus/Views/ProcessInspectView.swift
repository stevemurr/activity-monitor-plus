import SwiftUI

struct ProcessInspectView: View {
    @Environment(\.dismiss) private var dismiss
    let row: ProcessRow
    let details: ProcessDetails
    let events: [ConnectionEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(details.name)
                        .font(.title3.weight(.semibold))
                    Text("PID \(details.pid)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(.bottom, 12)

            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 6) {
                if let path = details.path {
                    infoRow("Path") {
                        Text(path)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .accessibilityIdentifier("inspect.path")
                    }
                }
                if let user = details.user {
                    infoRow("User") { Text(user) }
                }
                if let parent = details.parentPid {
                    infoRow("Parent PID") { Text(String(parent)).monospacedDigit() }
                }
                if let start = details.startDate {
                    infoRow("Started") {
                        Text(start, format: .dateTime.month().day().hour().minute())
                    }
                }
                infoRow("CPU") {
                    Text(row.cpuFraction.map { Format.percent($0) } ?? "unavailable")
                        .monospacedDigit()
                }
                infoRow("Memory") {
                    Text(row.residentBytes.map(Format.bytes) ?? "unavailable")
                        .monospacedDigit()
                }
            }

            if !events.isEmpty {
                Divider()
                    .padding(.vertical, 10)
                Text("Recent Network Activity")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(events) { event in
                        HStack(spacing: 8) {
                            Text(event.kind.rawValue)
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .leading)
                            Text(event.remote)
                                .monospacedDigit()
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("↓\(Format.bytes(event.bytesIn)) ↑\(Format.bytes(event.bytesOut))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }

            Spacer(minLength: 16)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("inspect.done")
            }
        }
        .padding(20)
        .frame(width: 440)
        .frame(minHeight: 260)
        // No identifier on this container: on macOS a container-level
        // accessibilityIdentifier propagates to every descendant and
        // clobbers their own identifiers.
    }

    private func infoRow(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}
