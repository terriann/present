import Foundation

/// Available color palettes for the app's design system.
public enum ColorPalette: String, CaseIterable, Codable, Sendable {
    case basic
    case modern

    public var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .modern: return "Modern"
        }
    }
}
