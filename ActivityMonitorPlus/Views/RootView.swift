import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, processes, network

    // The id type must match the List selection type, or row selection
    // silently never binds.
    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .processes: "Processes"
        case .network: "Network"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .processes: "tablecells"
        case .network: "network"
        }
    }
}

struct RootView: View {
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
                    .accessibilityIdentifier("sidebar.\(item.rawValue)")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView()
            case .processes: ProcessTableView()
            case .network: NetworkLogView()
            }
        }
        .frame(minWidth: 980, minHeight: 640)
    }
}
