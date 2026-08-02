import AppKit
import Observation
import SwiftUI

/// Drives one on-demand scan and the drill-down navigation over its result.
/// Owned by `StorageBreakdownView`; cancels its background scan on teardown.
@MainActor @Observable
final class StorageScanController {
    enum Phase: Equatable { case scanning, done }

    private(set) var phase: Phase = .scanning
    private(set) var progress = ScanProgress(filesScanned: 0, bytesScanned: 0)
    private(set) var result: StorageScanResult?
    /// Path from the scanned volume root down to the currently displayed node.
    private(set) var breadcrumb: [StorageNode] = []

    var currentRoot: StorageNode? { breadcrumb.last }

    private let scanner: any DiskScanning
    private let volume: VolumeInfo
    // Mutated only on the main actor (start/cancel); read once in deinit, which
    // is nonisolated on a @MainActor class.
    private nonisolated(unsafe) var task: Task<Void, Never>?

    init(scanner: any DiskScanning, volume: VolumeInfo) {
        self.scanner = scanner
        self.volume = volume
    }

    func start() {
        guard task == nil else { return }
        let scanner = self.scanner
        let url = URL(fileURLWithPath: volume.path)
        let name = volume.name
        let used = volume.usedBytes
        task = Task(priority: .utility) { [weak self] in
            let onProgress: @Sendable (ScanProgress) -> Void = { tick in
                Task { @MainActor in self?.progress = tick }
            }
            let result = await scanner.scan(volumeRoot: url, volumeName: name,
                                            usedBytes: used, progress: onProgress)
            await MainActor.run {
                guard let self, !result.cancelled else { return }
                self.apply(result)
            }
        }
    }

    private func apply(_ result: StorageScanResult) {
        self.result = result
        breadcrumb = [result.root]
        phase = .done
    }

    func drill(into node: StorageNode) {
        guard node.isNavigable else { return }
        breadcrumb.append(node)
    }

    func jump(toIndex index: Int) {
        guard index >= 0, index < breadcrumb.count else { return }
        breadcrumb = Array(breadcrumb.prefix(index + 1))
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}

/// Full-window sheet: scans the chosen volume, then shows a nested sunburst plus
/// a DaisyDisk-style legend list that both drill into folders.
struct StorageBreakdownView: View {
    let volume: VolumeInfo
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controller: StorageScanController?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if let controller, controller.phase == .done, let root = controller.currentRoot {
                    breakdown(controller: controller, root: root)
                } else {
                    scanning
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 560)
        .accessibilityIdentifier("storage.breakdown.root")
        .onAppear {
            if controller == nil {
                let created = StorageScanController(scanner: model.diskScanner, volume: volume)
                controller = created
                created.start()
            }
        }
        .onDisappear { controller?.cancel() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.title2.weight(.semibold))
                Text("Storage breakdown")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.bytes(volume.usedBytes) + " used")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("storage.breakdown.done")
        }
        .padding(16)
    }

    private var scanning: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning \(volume.name)…")
                .font(.headline)
            Text("\(controller?.progress.filesScanned ?? 0) items · \(Format.bytes(controller?.progress.bytesScanned ?? 0))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityIdentifier("storage.breakdown.progress")
    }

    private func breakdown(controller: StorageScanController, root: StorageNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            breadcrumbBar(controller: controller)
            if let result = controller.result, result.deniedCount > 100 {
                fullDiskAccessBanner
            }
            HStack(alignment: .center, spacing: 24) {
                ZStack {
                    SunburstView(root: root) { controller.drill(into: $0) }
                        .frame(width: 360, height: 360)
                    VStack(spacing: 1) {
                        Text(Format.bytes(root.sizeBytes))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .accessibilityIdentifier("storage.breakdown.total")
                        Text(root.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 120)
                    }
                }
                legend(controller: controller, root: root)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
    }

    private func breadcrumbBar(controller: StorageScanController) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(controller.breadcrumb.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(node.name) { controller.jump(toIndex: index) }
                        .buttonStyle(.plain)
                        .foregroundStyle(index == controller.breadcrumb.count - 1 ? .primary : Color.accentColor)
                        .lineLimit(1)
                        .accessibilityIdentifier("storage.breakdown.crumb.\(node.name)")
                }
            }
        }
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Some folders couldn't be read")
                    .font(.callout.weight(.medium))
                Text("Grant Full Disk Access for a complete scan; unreadable space shows as “System / hidden space.”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant Full Disk Access…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("storage.breakdown.fdaBanner")
    }

    private func legend(controller: StorageScanController, root: StorageNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(root.children.enumerated()), id: \.element.id) { index, child in
                    legendRow(controller: controller, child: child, colorIndex: index)
                }
            }
            // Reserve a gutter for the overlay scrollbar so, on a long list, it
            // floats beside the rows instead of over their trailing chevron/size.
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendRow(controller: StorageScanController, child: StorageNode,
                           colorIndex: Int) -> some View {
        let arc = SunburstArc(nodeID: child.id, name: child.name, sizeBytes: child.sizeBytes,
                              kind: child.kind, depth: 1, start: 0, end: 0, colorIndex: colorIndex)
        return Button {
            controller.drill(into: child)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(StorageSlicePalette.color(for: arc))
                    .frame(width: 10, height: 10)
                Text(child.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 16)
                Text(Format.bytes(child.sizeBytes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(child.isNavigable ? .secondary : Color.clear)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!child.isNavigable)
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storage.breakdown.legend.\(child.name)")
    }
}
