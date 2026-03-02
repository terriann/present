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

    // MARK: - Appearance Mode

    public var appearanceMode: AppearanceMode = .system

    /// Whether the system is currently using dark mode.
    /// Tracked by Observation so `preferredColorScheme` updates when the system toggles.
    private(set) var systemIsDark: Bool = false

    @ObservationIgnored
    private var appearanceObservation: NSKeyValueObservation?

    /// Returns the `ColorScheme` for `.preferredColorScheme()`.
    /// Always explicit — never `nil` — to avoid the macOS transition glitch
    /// where the title bar updates before the SwiftUI content when switching
    /// between a forced mode and system default.
    public var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return systemIsDark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Returns the `NSAppearance` to apply to NSPanel chrome, or `nil` for system default.
    public var nsAppearance: NSAppearance? {
        switch appearanceMode {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    public init() {
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        systemIsDark = isDark

        appearanceObservation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
            let nowDark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            Task { @MainActor [weak self] in
                self?.systemIsDark = nowDark
            }
        }
    }

    // MARK: - Semantic Tokens

    /// Brand identity color — used for app chrome, headers, and branding.
    public var primary: Color { Self.primaryColor(for: activePalette) }

    /// Interactive accent — buttons, selections, links, hover states.
    public var accent: Color { Self.accentColor(for: activePalette) }

    /// Positive/completed state (e.g. completed sessions).
    public var success: Color { Self.successColor(for: activePalette) }

    /// Caution/paused state (e.g. paused sessions).
    public var warning: Color { Self.warningColor(for: activePalette) }

    /// Destructive/error state (e.g. cancel, danger zone).
    public var alert: Color { Self.alertColor(for: activePalette) }

    // MARK: - Palette Preview

    /// Returns the five semantic colors for a given palette (for swatch previews).
    /// Uses static color lookup to avoid mutating the observed `activePalette`.
    public static func previewColors(for palette: ColorPalette) -> [Color] {
        [
            primaryColor(for: palette),
            accentColor(for: palette),
            successColor(for: palette),
            warningColor(for: palette),
            alertColor(for: palette),
        ]
    }

    // MARK: - Chart Colors

    /// Returns an array of 15 distinguishing colors for chart series, harmonized with the palette.
    /// The first 5 are the semantic tokens; the remaining 10 provide additional contrast.
    public static func chartColors(for palette: ColorPalette) -> [Color] {
        let semantic = previewColors(for: palette)
        let extra: [Color]
        switch palette {
        case .basic:
            extra = [
                Color(light: Color(hex: 0x8B5CF6), dark: Color(hex: 0xA78BFA)),  // violet
                Color(light: Color(hex: 0x06B6D4), dark: Color(hex: 0x22D3EE)),  // cyan
                Color(light: Color(hex: 0xD946EF), dark: Color(hex: 0xE879F9)),  // fuchsia
                Color(light: Color(hex: 0x84CC16), dark: Color(hex: 0xA3E635)),  // lime
                Color(light: Color(hex: 0xF97316), dark: Color(hex: 0xFB923C)),  // orange
                Color(light: Color(hex: 0x4F46E5), dark: Color(hex: 0x6366F1)),  // indigo
                Color(light: Color(hex: 0x0D9488), dark: Color(hex: 0x14B8A6)),  // teal
                Color(light: Color(hex: 0xE11D48), dark: Color(hex: 0xFB7185)),  // rose
                Color(light: Color(hex: 0xB45309), dark: Color(hex: 0xD97706)),  // amber
                Color(light: Color(hex: 0x475569), dark: Color(hex: 0x64748B)),  // slate
            ]
        case .modern:
            extra = [
                Color(light: Color(hex: 0x6366F1), dark: Color(hex: 0x818CF8)),  // indigo
                Color(light: Color(hex: 0x14B8A6), dark: Color(hex: 0x2DD4BF)),  // teal
                Color(light: Color(hex: 0xEC4899), dark: Color(hex: 0xF472B6)),  // pink
                Color(light: Color(hex: 0xEAB308), dark: Color(hex: 0xFACC15)),  // yellow
                Color(light: Color(hex: 0x78716C), dark: Color(hex: 0xA8A29E)),  // stone
                Color(light: Color(hex: 0x0891B2), dark: Color(hex: 0x06B6D4)),  // cyan
                Color(light: Color(hex: 0x059669), dark: Color(hex: 0x10B981)),  // emerald
                Color(light: Color(hex: 0x7C3AED), dark: Color(hex: 0x8B5CF6)),  // violet
                Color(light: Color(hex: 0xF43F5E), dark: Color(hex: 0xFB7185)),  // rose
                Color(light: Color(hex: 0xD97706), dark: Color(hex: 0xF59E0B)),  // amber
            ]
        case .dusty:
            extra = [
                Color(light: Color(hex: 0x6D597A), dark: Color(hex: 0x8B7198)),  // mauve
                Color(light: Color(hex: 0xB56576), dark: Color(hex: 0xCB7A8C)),  // rose
                Color(light: Color(hex: 0xE8AC65), dark: Color(hex: 0xEBBE82)),  // sand
                Color(light: Color(hex: 0x355070), dark: Color(hex: 0x4A6D8C)),  // slate blue
                Color(light: Color(hex: 0x56876D), dark: Color(hex: 0x6B9E82)),  // sage
                Color(light: Color(hex: 0xA0674B), dark: Color(hex: 0xB8806A)),  // terracotta
                Color(light: Color(hex: 0x7B4F82), dark: Color(hex: 0x9668A0)),  // plum
                Color(light: Color(hex: 0x6B7B4A), dark: Color(hex: 0x849660)),  // olive
                Color(light: Color(hex: 0xC67B6E), dark: Color(hex: 0xD99489)),  // dusty coral
                Color(light: Color(hex: 0x9C8A50), dark: Color(hex: 0xB4A268)),  // dusty gold
            ]
        }
        return semantic + extra
    }

    // MARK: - Static Color Lookup

    private static let basicPrimaryLight = Color(red: 0.584, green: 0.737, blue: 1.0)
    private static let basicPrimaryDark = Color(red: 0.439, green: 0.624, blue: 1.0)

    private static func primaryColor(for palette: ColorPalette) -> Color {
        switch palette {
        case .basic: Color(light: basicPrimaryLight, dark: basicPrimaryDark)
        case .modern: Color(light: Color(hex: 0x5da89c), dark: Color(hex: 0x70c1b3))
        case .dusty: Color(light: Color(hex: 0x7a2445), dark: Color(hex: 0x8f2d56))
        }
    }

    private static func accentColor(for palette: ColorPalette) -> Color {
        switch palette {
        case .basic: Color(light: Color(hex: 0xe47e1e), dark: Color(hex: 0xffa042))
        case .modern: Color(light: Color(hex: 0xbfcc85), dark: Color(hex: 0xd4e09b))
        case .dusty: Color(light: Color(hex: 0xd98a45), dark: Color(hex: 0xf4a259))
        }
    }

    private static func successColor(for palette: ColorPalette) -> Color {
        switch palette {
        case .basic: Color(
            light: Color(red: 0.204, green: 0.780, blue: 0.349),
            dark: Color(red: 0.188, green: 0.820, blue: 0.345)
        )
        case .modern: Color(light: Color(hex: 0x7a2d70), dark: Color(hex: 0x8f3985))
        case .dusty: Color(light: Color(hex: 0x698d94), dark: Color(hex: 0x7ea2aa))
        }
    }

    private static func warningColor(for palette: ColorPalette) -> Color {
        switch palette {
        case .basic: Color(
            light: Color(red: 0.961, green: 0.651, blue: 0.137),
            dark: Color(red: 1.0, green: 0.702, blue: 0.251)
        )
        case .modern: Color(light: Color(hex: 0x5a8ae6), dark: Color(hex: 0x709fff))
        case .dusty: Color(light: Color(hex: 0x737890), dark: Color(hex: 0x888da7))
        }
    }

    private static func alertColor(for palette: ColorPalette) -> Color {
        switch palette {
        case .basic: Color(
            light: Color(red: 1.0, green: 0.231, blue: 0.188),
            dark: Color(red: 1.0, green: 0.271, blue: 0.227)
        )
        case .modern: Color(light: Color(hex: 0xd95a3c), dark: Color(hex: 0xee6c4d))
        case .dusty: Color(light: Color(hex: 0xa27499), dark: Color(hex: 0xbc8da7))
        }
    }
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
