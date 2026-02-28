import SwiftUI

/// A button style for session control buttons (pause, resume, stop, cancel)
/// that provides hover feedback with a scale and circular background fill.
///
/// Respects Reduce Motion via `withAdaptiveAnimation`.
struct SessionControlButtonStyle: ButtonStyle {
    /// The color used for the hover background fill. Defaults to `.primary`.
    /// Pass `theme.alert` for destructive buttons like Stop.
    var hoverColor: Color = .primary

    /// Opacity when not hovered. Set below 1.0 to de-emphasize the button at rest.
    var restingOpacity: Double = 1.0

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isHovered ? 1.0 : restingOpacity)
            .scaleEffect(isHovered ? 1.08 : 1.0)
            .background(
                Circle()
                    .fill(hoverColor.opacity(isHovered ? 0.12 : 0))
                    .scaleEffect(1.4)
            )
            .onHover { hovering in
                withAdaptiveAnimation(.easeInOut(duration: 0.3)) {
                    isHovered = hovering
                }
            }
    }
}
