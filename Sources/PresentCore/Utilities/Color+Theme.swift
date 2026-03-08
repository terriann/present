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

    /// Applies the current appearance mode to the entire app process.
    ///
    /// Sets `NSApp.appearance` so that all windows — including the MenuBarExtra
    /// popover, which doesn't respect SwiftUI's `.preferredColorScheme()` — use
    /// the correct appearance. Call this whenever `appearanceMode` changes.
    public func applyAppearance() {
        NSApp?.appearance = nsAppearance
    }

    public init() {
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        systemIsDark = isDark

        appearanceObservation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                let nowDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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

    // MARK: - Constant Tokens

    /// Constant black — not affected by palette. Use for fixed dark backgrounds (e.g. terminal mock).
    public var constantBlack: Color { .black }

    /// Constant white — not affected by palette. Use for fixed light overlays (e.g. chart grid lines).
    public var constantWhite: Color { .white }

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
        case .nordic:
            extra = [
                Color(light: Color(hex: 0x4A7A9B), dark: Color(hex: 0x7AB0CC)),  // fjord blue
                Color(light: Color(hex: 0x6B8E6B), dark: Color(hex: 0x8FB88F)),  // pine
                Color(light: Color(hex: 0x9C7A5A), dark: Color(hex: 0xC4A47E)),  // birch
                Color(light: Color(hex: 0x7A6B8A), dark: Color(hex: 0xA494B4)),  // heather
                Color(light: Color(hex: 0xB07050), dark: Color(hex: 0xD4947A)),  // copper
                Color(light: Color(hex: 0x5A7A7A), dark: Color(hex: 0x82A8A8)),  // frost
                Color(light: Color(hex: 0x8A7A4A), dark: Color(hex: 0xB4A474)),  // lichen
                Color(light: Color(hex: 0x6A5A7A), dark: Color(hex: 0x9484A4)),  // twilight
                Color(light: Color(hex: 0x7A8A5A), dark: Color(hex: 0xA4B484)),  // moss
                Color(light: Color(hex: 0x8A6A6A), dark: Color(hex: 0xB49494)),  // granite
            ]
        case .rose:
            extra = [
                Color(light: Color(hex: 0xBE185D), dark: Color(hex: 0xF472B6)),  // deep rose
                Color(light: Color(hex: 0x6D5A2C), dark: Color(hex: 0xB8963C)),  // antique gold
                Color(light: Color(hex: 0x3B6B5C), dark: Color(hex: 0x5CA88A)),  // jade
                Color(light: Color(hex: 0x7C3AED), dark: Color(hex: 0xA78BFA)),  // violet
                Color(light: Color(hex: 0xA0522D), dark: Color(hex: 0xD4885C)),  // sienna
                Color(light: Color(hex: 0x2563EB), dark: Color(hex: 0x60A5FA)),  // royal blue
                Color(light: Color(hex: 0x7A5C4A), dark: Color(hex: 0xA88674)),  // walnut
                Color(light: Color(hex: 0x0E7490), dark: Color(hex: 0x22D3EE)),  // teal
                Color(light: Color(hex: 0x9A5A8A), dark: Color(hex: 0xC484B4)),  // mauve
                Color(light: Color(hex: 0x6B7A3A), dark: Color(hex: 0x95A464)),  // olive
            ]
        case .indigo:
            extra = [
                Color(light: Color(hex: 0x7C3AED), dark: Color(hex: 0xA78BFA)),  // violet
                Color(light: Color(hex: 0x0891B2), dark: Color(hex: 0x06B6D4)),  // cyan
                Color(light: Color(hex: 0xDB2777), dark: Color(hex: 0xF472B6)),  // pink
                Color(light: Color(hex: 0xD97706), dark: Color(hex: 0xF59E0B)),  // amber
                Color(light: Color(hex: 0x059669), dark: Color(hex: 0x10B981)),  // emerald
                Color(light: Color(hex: 0x9333EA), dark: Color(hex: 0xC084FC)),  // purple
                Color(light: Color(hex: 0xE11D48), dark: Color(hex: 0xFB7185)),  // rose
                Color(light: Color(hex: 0x65A30D), dark: Color(hex: 0x84CC16)),  // lime
                Color(light: Color(hex: 0x0D9488), dark: Color(hex: 0x14B8A6)),  // teal
                Color(light: Color(hex: 0x78716C), dark: Color(hex: 0xA8A29E)),  // stone
            ]
        case .terra:
            extra = [
                Color(light: Color(hex: 0x8B6914), dark: Color(hex: 0xC4A24A)),  // ochre
                Color(light: Color(hex: 0x6B4A3A), dark: Color(hex: 0x957464)),  // clay
                Color(light: Color(hex: 0x4A6E50), dark: Color(hex: 0x74987A)),  // fern
                Color(light: Color(hex: 0x8A5A5A), dark: Color(hex: 0xB48484)),  // sandstone
                Color(light: Color(hex: 0x5A6A7A), dark: Color(hex: 0x8494A4)),  // slate
                Color(light: Color(hex: 0x7A6A3A), dark: Color(hex: 0xA49464)),  // wheat
                Color(light: Color(hex: 0x6A5A4A), dark: Color(hex: 0x948474)),  // driftwood
                Color(light: Color(hex: 0x4A7A6A), dark: Color(hex: 0x74A494)),  // sage
                Color(light: Color(hex: 0x9A5A3A), dark: Color(hex: 0xC48464)),  // adobe
                Color(light: Color(hex: 0x5A7A4A), dark: Color(hex: 0x84A474)),  // moss
            ]
        }
        return semantic + extra
    }

    // MARK: - Static Color Lookup

    private static func primaryColor(for palette: ColorPalette) -> Color {
        switch palette {
        case .basic: Color(light: Color(hex: 0x166BFF), dark: Color(hex: 0x709FFF))
        case .modern: Color(light: Color(hex: 0x458077), dark: Color(hex: 0x70C1B3))
        case .dusty: Color(light: Color(hex: 0x7A2445), dark: Color(hex: 0xD3759C))
        case .nordic: Color(light: Color(hex: 0x2E5C8A), dark: Color(hex: 0x6BA3D6))
        case .rose: Color(light: Color(hex: 0x9F1239), dark: Color(hex: 0xFB7185))
        case .indigo: Color(light: Color(hex: 0x4338CA), dark: Color(hex: 0x818CF8))
        case .terra: Color(light: Color(hex: 0xA0522D), dark: Color(hex: 0xD4885C))
        }
    }

    private static func accentColor(for palette: ColorPalette) -> Color {
        switch palette {
        case .basic: Color(light: Color(hex: 0xB26115), dark: Color(hex: 0xFFA042))
        case .modern: Color(light: Color(hex: 0x8A9A3B), dark: Color(hex: 0xA4B84E))
        case .dusty: Color(light: Color(hex: 0xAE6424), dark: Color(hex: 0xF4A259))
        case .nordic: Color(light: Color(hex: 0x7A6340), dark: Color(hex: 0xC4A265))
        case .rose: Color(light: Color(hex: 0x7E5A2C), dark: Color(hex: 0xD4A056))
        case .indigo: Color(light: Color(hex: 0x0E7490), dark: Color(hex: 0x0EA5C0))
        case .terra: Color(light: Color(hex: 0x5B7553), dark: Color(hex: 0x88AC7E))
        }
    }

    private static func successColor(for palette: ColorPalette) -> Color {
        switch palette {
        case .basic: Color(light: Color(hex: 0x24883D), dark: Color(hex: 0x30D158))
        case .modern: Color(light: Color(hex: 0x7A2D70), dark: Color(hex: 0xC977BF))
        case .dusty: Color(light: Color(hex: 0x698D94), dark: Color(hex: 0x7EA2AA))
        case .nordic: Color(light: Color(hex: 0x3A7D5C), dark: Color(hex: 0x5CB88A))
        case .rose: Color(light: Color(hex: 0x166534), dark: Color(hex: 0x4ADE80))
        case .indigo: Color(light: Color(hex: 0x15803D), dark: Color(hex: 0x4ADE80))
        case .terra: Color(light: Color(hex: 0x2D6E5A), dark: Color(hex: 0x5AAE8E))
        }
    }

    private static func warningColor(for palette: ColorPalette) -> Color {
        switch palette {
        case .basic: Color(light: Color(hex: 0xA56A08), dark: Color(hex: 0xFFB340))
        case .modern: Color(light: Color(hex: 0x5A8AE6), dark: Color(hex: 0x709FFF))
        case .dusty: Color(light: Color(hex: 0x737890), dark: Color(hex: 0x888DA7))
        case .nordic: Color(light: Color(hex: 0x8B6914), dark: Color(hex: 0xD4A84B))
        case .rose: Color(light: Color(hex: 0x92400E), dark: Color(hex: 0xFB923C))
        case .indigo: Color(light: Color(hex: 0xA16207), dark: Color(hex: 0xFACC15))
        case .terra: Color(light: Color(hex: 0x946B2D), dark: Color(hex: 0xCFA04D))
        }
    }

    private static func alertColor(for palette: ColorPalette) -> Color {
        switch palette {
        case .basic: Color(light: Color(hex: 0xFF3B30), dark: Color(hex: 0xFF453A))
        case .modern: Color(light: Color(hex: 0xD95A3C), dark: Color(hex: 0xEE6C4D))
        case .dusty: Color(light: Color(hex: 0xA27499), dark: Color(hex: 0xBC8DA7))
        case .nordic: Color(light: Color(hex: 0xB83A3A), dark: Color(hex: 0xE86565))
        case .rose: Color(light: Color(hex: 0xB91C1C), dark: Color(hex: 0xFCA5A5))
        case .indigo: Color(light: Color(hex: 0xDC2626), dark: Color(hex: 0xF87171))
        case .terra: Color(light: Color(hex: 0xC23B22), dark: Color(hex: 0xE8614A))
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
