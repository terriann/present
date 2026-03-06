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
                    SidebarNavItem(
                        item: item,
                        isSelected: state.selectedSidebarItem == item
                    ) {
                        state.selectedSidebarItem = item
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    Label("Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Constants.spacingToolbar)
                        .padding(.vertical, Constants.spacingCompact)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture { openSettings() }
                }
            }
        } detail: {
            ZoomContainer(scale: appState.zoomScale) {
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
}

// MARK: - Sidebar Nav Item

private struct SidebarNavItem: View {
    @Environment(ThemeManager.self) private var theme

    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Label(item.rawValue, systemImage: item.icon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? .white : .primary)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? theme.accent.opacity(0.6) : Color.clear)
            )
    }
}
