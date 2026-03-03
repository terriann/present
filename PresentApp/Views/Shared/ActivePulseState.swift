import SwiftUI
import PresentCore

/// Observable sine wave opacity driver for chart mark pulsing on active sessions.
///
/// Use this when you need a `Double` opacity value (e.g., for Swift Charts mark opacity)
/// rather than a SwiftUI view modifier. For view-level pulsing, use `.activePulse()` instead.
@MainActor @Observable
final class ActivePulseState {
    var opacity: Double = 1.0

    private var task: Task<Void, Never>?

    /// Begin the pulse animation loop using `Constants.activePulse*` values.
    ///
    /// When `reduceMotion` is true, opacity stays at 1.0 (no animation).
    func start(reduceMotion: Bool) {
        stop()

        guard !reduceMotion else {
            opacity = 1.0
            return
        }

        let midpoint = (Constants.activePulseHigh + Constants.activePulseLow) / 2
        let amplitude = (Constants.activePulseHigh - Constants.activePulseLow) / 2
        let period = Constants.activePulseDuration * 2 + Constants.activePulseDelay

        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Constants.activePulseInterval))
                let t = Date().timeIntervalSinceReferenceDate
                self.opacity = midpoint + amplitude * sin(t * 2 * .pi / period)
            }
        }
    }

    /// Stop the pulse and reset opacity to full.
    func stop() {
        task?.cancel()
        task = nil
        opacity = 1.0
    }
}
