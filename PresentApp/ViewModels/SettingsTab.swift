import Foundation

enum SettingsTab: String, CaseIterable {
    case general, cli, sessions, notifications, about

    var label: String {
        switch self {
        case .general: "General"
        case .cli: "CLI"
        case .sessions: "Sessions"
        case .notifications: "Notifications"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .cli: "terminal"
        case .sessions: "timer"
        case .notifications: "bell"
        case .about: "info.circle"
        }
    }
}
