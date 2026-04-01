import PresentCore
import SwiftUI

/// A subtle "Data reloaded" indicator that fades in and out when Command+R is pressed.
/// Respects Reduce Motion — uses a quick crossfade instead of a slide when enabled.
struct ReloadFeedbackOverlay: ViewModifier {
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isVisible {
                HStack(spacing: Constants.spacingCompact) {
                    Image(systemName: "arrow.clockwise")
                        .font(.controlIconSmall)
                        .accessibilityHidden(true)
                    Text("Data reloaded")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .accessibilityLabel("Data reloaded")
                .padding(.horizontal, Constants.spacingCard)
                .padding(.vertical, Constants.spacingTight)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                )
            }
        }
        .adaptiveAnimation(.easeInOut(duration: 0.3), value: isVisible)
    }
}

extension View {
    func reloadFeedback(isVisible: Bool) -> some View {
        modifier(ReloadFeedbackOverlay(isVisible: isVisible))
    }
}
