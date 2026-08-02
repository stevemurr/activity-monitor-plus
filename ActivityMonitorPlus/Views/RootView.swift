import SwiftUI

struct NavigateSidebarAction: @unchecked Sendable {
    private let handler: @MainActor (SidebarItem) -> Void

    init(_ handler: @escaping @MainActor (SidebarItem) -> Void) {
        self.handler = handler
    }

    @MainActor func callAsFunction(_ item: SidebarItem) {
        handler(item)
    }
}

private struct NavigateSidebarKey: EnvironmentKey {
    static let defaultValue = NavigateSidebarAction { _ in }
}

extension EnvironmentValues {
    var navigateSidebar: NavigateSidebarAction {
        get { self[NavigateSidebarKey.self] }
        set { self[NavigateSidebarKey.self] = newValue }
    }
}

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
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                    Text("Activity Monitor Plus")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                List(SidebarItem.allCases, selection: $selection) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                        .accessibilityIdentifier("sidebar.\(item.rawValue)")
                }
                .listStyle(.sidebar)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(14)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView()
            case .processes: ProcessTableView()
            case .network: NetworkLogView()
            }
        }
        .environment(\.navigateSidebar, NavigateSidebarAction { item in selection = item })
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1080, minHeight: 700)
    }
}
