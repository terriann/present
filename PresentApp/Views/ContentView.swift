import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            List(SidebarItem.allCases, selection: $state.selectedSidebarItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
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
