import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    CPUDonutCard()
                        .frame(maxWidth: .infinity)
                        .layoutPriority(2)
                    MemoryCard()
                        .frame(width: 330)
                }
                HStack(alignment: .top, spacing: 16) {
                    NetworkCard()
                        .frame(maxWidth: .infinity)
                        .layoutPriority(2)
                    StorageCard()
                        .frame(width: 330)
                }
            }
            .padding(20)
        }
        .navigationTitle("Overview")
        .navigationSubtitle("\(Host.current().localizedName ?? "This Mac") · Updated just now")
        .toolbar {
            ToolbarItem {
                StatusPill(title: "Live")
            }
        }
        .accessibilityIdentifier("overview.root")
    }
}
