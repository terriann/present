#if canImport(SwiftUI)
import SwiftUI

/// Observable theme manager that provides semantic color tokens.
///
/// Injected into the SwiftUI environment so views can react to palette changes.
/// Access via `@Environment(ThemeManager.self) private var theme`.
@MainActor @Observable
public final class ThemeManager {

    // MARK: - Active Palette

    public var activePalette: ColorPalette = .basic

    public init() {}

    // MARK: - Semantic Tokens

    /// Brand identity color — used for app chrome, headers, and branding.
    public var primary: Color {
        switch activePalette {
        case .basic:
            return Color(light: basicPrimaryLight, dark: basicPrimaryDark)
        case .modern:
            return Color(light: Color(hex: 0x3a3e5c), dark: Color(hex: 0x25283d))
        case .dusty:
            return Color(light: Color(hex: 0x6e7390), dark: Color(hex: 0x888da7))
        }
    }

    /// Interactive accent — buttons, selections, links, hover states.
    public var accent: Color {
        switch activePalette {
        case .basic:
            return Color(light: basicPrimaryLight, dark: basicPrimaryDark)
        case .modern:
            return Color(light: Color(hex: 0x5a8ae6), dark: Color(hex: 0x709fff))
        case .dusty:
            return Color(light: Color(hex: 0x698d94), dark: Color(hex: 0x7ea2aa))
        }
    }

    /// Positive/completed state (e.g. completed sessions).
    public var success: Color {
        switch activePalette {
        case .basic:
            return Color(
                light: Color(red: 0.204, green: 0.780, blue: 0.349),  // #34C759
                dark: Color(red: 0.188, green: 0.820, blue: 0.345)    // #30D158
            )
        case .modern:
            return Color(light: Color(hex: 0x5aab9e), dark: Color(hex: 0x70c1b3))
        case .dusty:
            return Color(light: Color(hex: 0x6dd0b3), dark: Color(hex: 0x8be8cb))
        }
    }

    /// Caution/paused state (e.g. paused sessions).
    public var warning: Color {
        switch activePalette {
        case .basic:
            return Color(
                light: Color(red: 0.961, green: 0.651, blue: 0.137),  // #F5A623
                dark: Color(red: 1.0, green: 0.702, blue: 0.251)      // #FFB340
            )
        case .modern:
            return Color(light: Color(hex: 0xd95a3c), dark: Color(hex: 0xee6c4d))
        case .dusty:
            return Color(light: Color(hex: 0xd98a45), dark: Color(hex: 0xf4a259))
        }
    }

    /// Destructive/error state (e.g. cancel, danger zone).
    public var alert: Color {
        switch activePalette {
        case .basic:
            return Color(
                light: Color(red: 1.0, green: 0.231, blue: 0.188),    // #FF3B30
                dark: Color(red: 1.0, green: 0.271, blue: 0.227)      // #FF453A
            )
        case .modern:
            return Color(light: Color(hex: 0x7a2d70), dark: Color(hex: 0x8f3985))
        case .dusty:
            return Color(light: Color(hex: 0x856880), dark: Color(hex: 0x9c7a97))
        }
    }

    // MARK: - Palette Preview

    /// Returns the five semantic colors for a given palette (for swatch previews).
    public func colors(for palette: ColorPalette) -> [Color] {
        let saved = activePalette
        activePalette = palette
        let result = [accent, success, warning, alert, primary]
        activePalette = saved
        return result
    }

    // MARK: - Basic Palette Base Colors

    /// Brand blue light variant: #95bcff
    private let basicPrimaryLight = Color(red: 0.584, green: 0.737, blue: 1.0)

    /// Brand blue dark variant: #709fff
    private let basicPrimaryDark = Color(red: 0.439, green: 0.624, blue: 1.0)
}

// MARK: - Light/Dark Adaptive Color

extension Color {
    /// Creates a color that adapts between light and dark appearance.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        }))
    }

    /// Creates a color from a hex integer (e.g. `0xFF3B30`).
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
#endif
