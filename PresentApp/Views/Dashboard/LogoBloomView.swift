import SwiftUI
import PresentCore

/// Subtle lotus bloom animation shown in the dashboard header.
///
/// Uses the exact petal shape from the Present logo SVG, arranged as
/// 7 petals fanning from -90° to +90°. On appear, petals start stacked
/// vertically at the base and unfurl outward to their final positions.
struct LogoBloomView: View {
    @Environment(ThemeManager.self) private var theme
    @State private var bloomed = false

    /// Petal angles matching the logo: center, ±30°, ±60°, ±90°.
    private let petalAngles: [Double] = [-90, -60, -30, 0, 30, 60, 90]

    var body: some View {
        GeometryReader { geo in
            // Size petals so the full fan spans 80% of the container width
            let petalHeight = geo.size.width * 0.8 / 2.0
            let petalWidth = petalHeight * 0.475

            ZStack {
                ForEach(Array(petalAngles.enumerated()), id: \.offset) { _, angle in
                    let delay = petalDelay(angle)

                    LotusPetalShape()
                        .fill(theme.primary.opacity(bloomed ? 0.06 : 0))
                        .frame(width: petalWidth, height: petalHeight)
                        .offset(y: -petalHeight * 0.45)
                        .rotationEffect(.degrees(bloomed ? angle : 0))
                        .scaleEffect(bloomed ? 1.0 : 0.3)
                        .adaptiveAnimation(
                            .easeOut(duration: 2.0).delay(delay),
                            reduced: .linear(duration: 0.3),
                            value: bloomed
                        )
                }
            }
            // Bottom-aligned: offset pivot up so the outermost petals rest at the container bottom
            .position(x: geo.size.width / 2, y: geo.size.height - petalWidth / 2)
        }
        .task {
            // Brief delay lets the GeometryReader settle before animating
            try? await Task.sleep(for: .milliseconds(100))
            bloomed = true
        }
    }

    // MARK: - Helpers

    /// Center petals unfurl first, outer petals follow.
    private func petalDelay(_ angle: Double) -> Double {
        abs(angle) / 90.0 * 0.3
    }
}

// MARK: - Petal Shape

/// The exact lotus petal from the Present logo SVG — a symmetric lens shape
/// narrow at the base (bottom), widest at the center, and tapering to the tip (top).
private struct LotusPetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        // Normalized control points extracted from the logo SVG path
        var path = Path()

        // Start at base (bottom center)
        path.move(to: CGPoint(x: w * 0.5, y: h))

        // Left side: base up to midpoint
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.5),
            control1: CGPoint(x: w * 0.195, y: h * 0.882),
            control2: CGPoint(x: 0, y: h * 0.701)
        )

        // Left side: midpoint up to tip
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: 0, y: h * 0.299),
            control2: CGPoint(x: w * 0.195, y: h * 0.118)
        )

        // Right side: tip down to midpoint
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.5),
            control1: CGPoint(x: w * 0.805, y: h * 0.118),
            control2: CGPoint(x: w, y: h * 0.299)
        )

        // Right side: midpoint down to base
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w, y: h * 0.701),
            control2: CGPoint(x: w * 0.805, y: h * 0.882)
        )

        return path
    }
}
