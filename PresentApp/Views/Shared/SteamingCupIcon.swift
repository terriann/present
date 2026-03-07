import SwiftUI
import PresentCore

/// Animated cup icon with gently oscillating steam wisps styled after
/// the SF Pro `cup.and.heat.waves` glyph. When Reduce Motion is enabled,
/// steam shows at a static opacity.
struct SteamingCupIcon: View {
    /// Icon size in points. Defaults to 48 for detail views; pass ~28 for inline use.
    var size: CGFloat = 48

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Scale factor relative to the default 48pt size.
    private var scale: CGFloat { size / 48 }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Steam wisps rising from the cup rim
            HStack(alignment: .bottom, spacing: 3 * scale) {
                AnimatedSteamWisp(height: 22 * scale, strokeWidth: 2.5 * scale, reduceMotion: reduceMotion)
                AnimatedSteamWisp(height: 28 * scale, strokeWidth: 2.5 * scale, reduceMotion: reduceMotion)
                AnimatedSteamWisp(height: 22 * scale, strokeWidth: 2.5 * scale, reduceMotion: reduceMotion)
            }
            .offset(y: -40 * scale)

            // Cup icon
            Image(systemName: "cup.and.saucer")
                .font(.system(size: size))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Animated Steam Wisp

/// Each wisp manages its own animation with a randomized duration and delay,
/// so the three wisps drift in and out of phase organically.
private struct AnimatedSteamWisp: View {
    let height: CGFloat
    var strokeWidth: CGFloat = 2.5
    let reduceMotion: Bool

    @State private var animating = false
    @State private var duration: Double = 2.0
    @State private var initialDelay: Double = 0

    var body: some View {
        SteamWispPath()
            .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
            .foregroundStyle(.secondary)
            .frame(width: strokeWidth * 4, height: height)
            .opacity(reduceMotion ? 0.25 : (animating ? 0.45 : 0.1))
            .adaptiveAnimation(
                .easeInOut(duration: duration)
                    .delay(initialDelay)
                    .repeatForever(autoreverses: true),
                reduced: .linear(duration: 0),
                value: animating
            )
            .onAppear {
                // Randomize each wisp's cycle independently
                duration = Double.random(in: 1.5...2.8)
                initialDelay = Double.random(in: 0...1.0)
                guard !reduceMotion else { return }
                animating = true
            }
            .onChange(of: reduceMotion) { _, newValue in
                animating = !newValue
            }
    }
}

// MARK: - Steam Wisp Path

/// Smooth S-curve resembling a single wisp from `cup.and.heat.waves`.
/// The curve sways right then left as it rises, like a tilde (~).
private struct SteamWispPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Start at bottom center
        path.move(to: CGPoint(x: w * 0.5, y: h))

        // Single smooth S-curve: sway right in the lower half, left in the upper half
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.5),
            control1: CGPoint(x: w * 0.5, y: h * 0.85),
            control2: CGPoint(x: w * 1.1, y: h * 0.6)
        )

        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: w * -0.1, y: h * 0.4),
            control2: CGPoint(x: w * 0.5, y: h * 0.15)
        )

        return path
    }
}
