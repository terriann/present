import SwiftUI
import PresentCore

/// A toggle style that renders a switch colored by the active palette.
///
/// macOS system toggles ignore `.tint()`, so this custom style draws
/// its own track and thumb to respect ThemeManager colors.
struct ThemedToggleStyle: ToggleStyle {
    let tintColor: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label

            Button {
                withAdaptiveAnimation(.snappy(duration: 0.15)) {
                    configuration.isOn.toggle()
                }
            } label: {
                RoundedRectangle(cornerRadius: 16, style: .circular)
                    .fill(configuration.isOn ? tintColor : Color.secondary.opacity(0.3))
                    .frame(width: 44, height: 26)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                            .padding(2)
                            .offset(x: configuration.isOn ? 9 : -9)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
