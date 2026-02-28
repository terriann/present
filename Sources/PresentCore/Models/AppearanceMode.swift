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
}
