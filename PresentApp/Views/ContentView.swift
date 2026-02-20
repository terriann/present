import SwiftUI
import PresentCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            List {
                ForEach(SidebarItem.allCases) { item in
                    Button {
                        state.selectedSidebarItem = item
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(state.selectedSidebarItem == item ? theme.primary : .primary)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(state.selectedSidebarItem == item ? theme.primary.opacity(0.15) : Color.clear)
                    )
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Constants.spacingToolbar)
                        .padding(.vertical, Constants.spacingCompact)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        } detail: {
            switch appState.selectedSidebarItem {
            case .dashboard:
                DashboardView()
            case .reports:
                ReportsView()
            case .activities:
                ActivitiesListView()
            }
        }
    }
}
