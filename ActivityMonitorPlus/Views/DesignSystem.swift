import AppKit
import SwiftUI

enum AMPStyle {
    static let blue = Color(nsColor: .systemBlue)
    static let purple = Color(nsColor: .systemPurple)
    static let orange = Color(nsColor: .systemOrange)
    static let green = Color(nsColor: .systemGreen)
    static let red = Color(nsColor: .systemRed)

    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let subtleFill = Color(nsColor: .windowBackgroundColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.55)
    static let track = Color(nsColor: .quaternaryLabelColor).opacity(0.55)
}

/// A color-blind-friendly categorical palette shared by process and storage
/// visualizations.
enum SlicePalette {
    static let processColors: [Color] = [
        AMPStyle.blue,
        AMPStyle.orange,
        AMPStyle.purple,
        AMPStyle.green,
        Color(nsColor: .systemPink),
    ]

    static func colors(for slices: [DonutSlice]) -> [(slice: DonutSlice, color: Color)] {
        var processIndex = 0
        return slices.map { slice in
            switch slice.category {
            case .process:
                let color = processColors[processIndex % processColors.count]
                processIndex += 1
                return (slice, color)
            case .other:
                return (slice, Color(nsColor: .systemGray))
            case .idle:
                return (slice, Color(nsColor: .quaternaryLabelColor))
            }
        }
    }
}

/// The shared surface used throughout the redesigned dashboard and detail tabs.
struct DashboardCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(AMPStyle.cardFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AMPStyle.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.025), radius: 2, y: 1)
            // Stop macOS accessibility from flattening adjacent dashboard
            // cards into one giant static-text element. Children retain their
            // own identifiers for XCUITest and VoiceOver navigation.
            .accessibilityElement(children: .contain)
    }
}

struct DashboardSectionTitle<Trailing: View>: View {
    let title: String
    let symbol: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, symbol: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.headline)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension DashboardSectionTitle where Trailing == EmptyView {
    init(_ title: String, symbol: String? = nil) {
        self.init(title, symbol: symbol) { EmptyView() }
    }
}

struct StatusPill: View {
    let title: String
    var color = AMPStyle.green

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: Capsule())
        .foregroundStyle(color)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var detail: String?
    var color = AMPStyle.blue
    var progress: Double?
    var symbol: String?

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(color)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                        .monospacedDigit()
                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AMPStyle.track)
                            Capsule().fill(color)
                                .frame(width: proxy.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
    }
}

/// `NSRunningApplication(processIdentifier:)` hits LaunchServices and `.icon`
/// reads the app bundle off disk (visible as `__getattrlist` and KVO hashing in
/// a main-thread sample). At ~27 µs per lookup that is ~4 ms for one 150-row
/// pass of the process table — repeated on every 1 Hz refresh and every click,
/// for icons that never change. Resolve once per pid instead.
@MainActor
private enum ProcessIconCache {
    private static var icons: [Int32: NSImage?] = [:]

    static func icon(for pid: Int32) -> NSImage? {
        if let cached = icons[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid_t(pid))?.icon
        // Bounded so a long session churning through short-lived pids cannot
        // grow this without limit. Dropping everything is fine: entries are
        // reconstructed on demand.
        if icons.count > 4096 { icons.removeAll() }
        icons[pid] = icon
        return icon
    }
}

/// Resolves a live application icon where possible and uses a stable native
/// fallback for system daemons and test fixtures.
struct ProcessIconView: View {
    let pid: Int32
    var size: CGFloat = 28

    private var runningIcon: NSImage? {
        ProcessIconCache.icon(for: pid)
    }

    var body: some View {
        Group {
            if let runningIcon {
                Image(nsImage: runningIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(AMPStyle.blue.gradient)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: size * 0.48, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Horizontal capacity bar with colored segments over a neutral track.
struct UsageBar: View {
    var segments: [(color: Color, fraction: Double)]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if segment.fraction > 0.001 {
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(1, geometry.size.width * segment.fraction))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .background(AMPStyle.track)
        .clipShape(Capsule())
        .frame(height: height)
    }
}

struct ResourceBar: View {
    let fraction: Double
    var color = AMPStyle.blue

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AMPStyle.track)
                Capsule().fill(color)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
    }
}
