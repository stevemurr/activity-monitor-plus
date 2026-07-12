import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Image + Text is the supported composition for a status item label.
        Image(systemName: "gauge.with.dots.needle.67percent")
        // Reserve the width of the widest value ("100%") and right-align the
        // current reading inside it, with monospaced digits, so the item's
        // width never changes as the percent updates (no menu-bar jitter).
        Text("100%")
            .monospacedDigit()
            .hidden()
            .overlay(alignment: .trailing) {
                Text(Format.percent(model.cpu.totalUsedFraction))
                    .monospacedDigit()
            }
    }
}

struct MenuBarContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row(symbol: "cpu", label: "CPU",
                    value: Format.percent(model.cpu.totalUsedFraction))
                if let memory = model.memory {
                    row(symbol: "memorychip", label: "Memory",
                        value: "\(Format.bytes(memory.usedBytes)) of \(Format.bytes(memory.totalBytes))")
                }
                row(symbol: "arrow.down", label: "Network In",
                    value: Format.rate(model.throughput.bytesInPerSecond))
                row(symbol: "arrow.up", label: "Network Out",
                    value: Format.rate(model.throughput.bytesOutPerSecond))
            }

            Divider()

            HStack {
                Button("Open Activity Monitor Plus") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .accessibilityIdentifier("menubar.open")
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .accessibilityIdentifier("menubar.quit")
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 280)
        // No container identifier: it would propagate to and clobber the
        // buttons' own identifiers (macOS AX behavior).
    }

    private func row(symbol: String, label: String, value: String) -> some View {
        GridRow {
            Label(label, systemImage: symbol)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout)
    }
}
