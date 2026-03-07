import SwiftUI
import PresentCore

struct SpinningClockIcon: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isRunning: Bool
    @State private var degrees: Double = 0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.subheadline)
            .foregroundStyle(theme.accent)
            .rotationEffect(.degrees(degrees))
            .onAppear {
                guard isRunning, !reduceMotion else { return }
                withAdaptiveAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    degrees = 360
                }
            }
            .onChange(of: isRunning) { _, running in
                if running, !reduceMotion {
                    withAdaptiveAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        degrees = 360
                    }
                } else {
                    withAdaptiveAnimation(.default) { degrees = 0 }
                }
            }
    }
}
