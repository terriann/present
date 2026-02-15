import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            List(SidebarItem.allCases, selection: $state.selectedSidebarItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch appState.selectedSidebarItem {
            case .dashboard:
                DashboardView()
            case .log:
                LogView()
            case .reports:
                ReportsView()
            case .activities:
                ActivitiesListView()
            }
        }
    }
}
