import Foundation

/// User preference for app appearance: follow macOS, or force light/dark.
public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// SF Symbol name for the appearance mode.
    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}
