import SwiftUI
import PresentCore

/// View modifier that applies a gentle pulse animation to active session elements.
///
/// Uses `.phaseAnimator` with `Constants.activePulse*` values for consistent timing
/// across the app. Respects Reduce Motion — when enabled, the view stays at full opacity.
///
/// Use this on SwiftUI views (stats, badges, labels) where a modifier is natural.
/// For chart mark opacity (where you need a `Double` value), use `ActivePulseState` instead.
struct ActivePulseModifier: ViewModifier {
    let isActive: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            content
                .phaseAnimator([Constants.activePulseHigh, Constants.activePulseLow]) { view, phase in
                    view.opacity(phase)
                } animation: { phase in
                    phase == Constants.activePulseLow
                        ? .easeInOut(duration: Constants.activePulseDuration).delay(Constants.activePulseDelay)
                        : .easeInOut(duration: Constants.activePulseDuration)
                }
        } else {
            content
        }
    }
}

extension View {
    /// Apply a gentle pulse animation when `isActive` is true.
    ///
    /// Respects the user's Reduce Motion preference — pass the environment value.
    func activePulse(isActive: Bool, reduceMotion: Bool) -> some View {
        modifier(ActivePulseModifier(isActive: isActive, reduceMotion: reduceMotion))
    }
}
