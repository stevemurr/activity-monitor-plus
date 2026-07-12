import SwiftUI

struct OverviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CPUDonutCard()
                HStack(alignment: .top, spacing: 16) {
                    MemoryCard()
                    NetworkCard()
                }
                StorageCard()
            }
            .padding(20)
        }
        .navigationTitle("Overview")
        .accessibilityIdentifier("overview.root")
    }
}

/// Shared native-styled card container.
struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Horizontal capacity bar with colored segments over a neutral track.
/// Segments get a hairline surface gap so adjacent fills never touch.
struct UsageBar: View {
    var segments: [(color: Color, fraction: Double)]

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
        .background(Color(nsColor: .quaternaryLabelColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .frame(height: 10)
    }
}
