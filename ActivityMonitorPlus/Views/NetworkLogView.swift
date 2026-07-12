import SwiftUI

struct NetworkLogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Table(model.connectionEvents) {
            TableColumn("Time") { event in
                Text(event.timestamp, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 80, max: 90)
            TableColumn("Event") { event in
                Label(event.kind.rawValue, systemImage: symbol(for: event.kind))
                    .foregroundStyle(color(for: event.kind))
            }
            .width(min: 80, ideal: 95, max: 110)
            TableColumn("Process") { event in
                Text(event.processName)
            }
            TableColumn("PID") { event in
                Text(String(event.pid))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60, max: 80)
            TableColumn("Remote Address") { event in
                Text(event.remote)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TableColumn("Proto") { event in
                Text(event.proto.rawValue.uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .width(min: 45, ideal: 50, max: 60)
            TableColumn("In") { event in
                Text(Format.bytes(event.bytesIn))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 75, max: 95)
            TableColumn("Out") { event in
                Text(Format.bytes(event.bytesOut))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 75, max: 95)
        }
        .accessibilityIdentifier("network.table")
        .overlay {
            if model.connectionEvents.isEmpty {
                ContentUnavailableView(
                    "No Network Events Yet",
                    systemImage: "network",
                    description: Text("Connection opens, closes, and traffic will appear here."))
            }
        }
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

    private func symbol(for kind: ConnectionEvent.Kind) -> String {
        switch kind {
        case .opened: "plus.circle.fill"
        case .closed: "xmark.circle.fill"
        case .traffic: "arrow.up.arrow.down.circle.fill"
        }
    }

    private func color(for kind: ConnectionEvent.Kind) -> Color {
        switch kind {
        case .opened: Color(nsColor: .systemGreen)
        case .closed: Color(nsColor: .secondaryLabelColor)
        case .traffic: Color(nsColor: .systemBlue)
        }
    }
}
