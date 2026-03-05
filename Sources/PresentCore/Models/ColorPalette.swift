import Foundation

/// Available color palettes for the app's design system.
public enum ColorPalette: String, CaseIterable, Codable, Sendable {
    case basic
    case modern
    case dusty
    case nordic
    case rose
    case indigo
    case terra

    public var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .modern: return "Modern"
        case .dusty: return "Dusty"
        case .nordic: return "Nordic"
        case .rose: return "Rosewood"
        case .indigo: return "Indigo Night"
        case .terra: return "Terra"
        }
    }
}
