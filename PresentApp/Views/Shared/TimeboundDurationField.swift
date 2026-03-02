import SwiftUI
import PresentCore

/// Shared duration input field for timebound sessions.
///
/// Two size presets control the visual presentation:
/// - **`.compact`**: Caption font, 48pt width, no visible label. Used in space-constrained
///   contexts like menu bar and inline convert controls.
/// - **`.regular`**: Callout font, 64pt width, visible "Duration:" label prefix. Used in sheets
///   and detail views.
///
/// Both sizes include a "min" suffix and an accessibility label for VoiceOver.
/// Pass `zoomScale` to scale font size and field width for the menu bar zoom feature.
struct TimeboundDurationField: View {
    @Binding var minutes: Int
    var size: Size = .regular
    var zoomScale: CGFloat = 1.0
    var autoFocus: Bool = false

    @FocusState private var isFocused: Bool

    enum Size {
        /// Caption font, 48pt width, no visible label.
        case compact
        /// Callout font, 64pt width, visible "Duration:" label prefix.
        case regular
    }

    // MARK: - Scaled Properties

    private var font: Font {
        if zoomScale != 1.0 {
            // Match MenuBarView.scaledFont base sizes: caption=10, callout=12
            let baseSize: CGFloat = size == .compact ? 10 : 12
            return .system(size: round(baseSize * zoomScale))
        }
        return size == .compact ? .caption : .callout
    }

    private var fieldWidth: CGFloat {
        (size == .compact ? 48 : 64) * zoomScale
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: size == .compact ? Constants.spacingTight : Constants.spacingCompact) {
            if size == .regular {
                Text("Duration:")
                    .font(font)
                    .foregroundStyle(.secondary)
            }

            TextField("", value: $minutes, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: fieldWidth)
                .font(font)
                .focused($isFocused)
                .accessibilityLabel("Duration in minutes")
                .onAppear {
                    if autoFocus {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            isFocused = true
                        }
                    }
                }

            Text("min")
                .font(font)
                .foregroundStyle(.secondary)
        }
    }
}
