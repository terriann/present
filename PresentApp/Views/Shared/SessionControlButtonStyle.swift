import SwiftUI

/// A button style for session control buttons (pause, resume, stop, cancel)
/// that provides hover feedback with a scale and circular background fill.
///
/// Matches the `.lift` hover pattern from `FloatingAlertView` with a 1.15 scale factor.
/// Respects Reduce Motion via `withAdaptiveAnimation`.
struct SessionControlButtonStyle: ButtonStyle {
    /// The color used for the hover background fill. Defaults to `.primary`.
    /// Pass `theme.alert` for destructive buttons like Stop.
    var hoverColor: Color = .primary

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isHovered ? 1.15 : 1.0)
            .background(
                Circle()
                    .fill(hoverColor.opacity(isHovered ? 0.15 : 0))
                    .scaleEffect(1.8)
            )
            .onHover { hovering in
                withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
    }
}
