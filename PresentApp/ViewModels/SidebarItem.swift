import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case activities = "Activities"
    case reports = "Reports"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .reports: return "chart.bar"
        case .activities: return "tray.full"
        }
    }
}
