import SwiftUI

// MARK: - View Modifier

/// Applies an animation that adapts to the user's reduce motion preference.
///
/// When Reduce Motion is enabled in System Settings > Accessibility > Display,
/// the reduced animation is used instead — typically a gentle linear fade
/// rather than spring or eased motion.
struct AdaptiveAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let standard: Animation
    let reduced: Animation
    let value: V

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? reduced : standard, value: value)
    }
}

// MARK: - View Extension

extension View {
    /// Applies an animation that respects the user's reduce motion preference.
    ///
    /// - Parameters:
    ///   - standard: The animation to use normally.
    ///   - reduced: The animation to use when Reduce Motion is on. Defaults to `.linear(duration: 0.15)`.
    ///   - value: The value to observe for changes.
    func adaptiveAnimation<V: Equatable>(
        _ standard: Animation,
        reduced: Animation = .linear(duration: 0.15),
        value: V
    ) -> some View {
        modifier(AdaptiveAnimationModifier(standard: standard, reduced: reduced, value: value))
    }
}

// MARK: - Imperative Function

/// A reduce-motion-aware replacement for `withAnimation(_:_:)`.
///
/// Reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` since
/// `@Environment` is not available outside SwiftUI views.
///
/// - Parameters:
///   - standard: The animation to use normally.
///   - reduced: The animation to use when Reduce Motion is on. Defaults to `.linear(duration: 0.15)`.
///   - body: The state mutation to animate.
func withAdaptiveAnimation<Result>(
    _ standard: Animation,
    reduced: Animation = .linear(duration: 0.15),
    _ body: () throws -> Result
) rethrows -> Result {
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    return try withAnimation(reduceMotion ? reduced : standard, body)
}
