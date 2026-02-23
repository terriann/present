import SwiftUI
import PresentCore

/// A compact edit button that expands into a labeled pill on hover.
///
/// Default state shows a `square.and.pencil` icon in secondary color.
/// On hover the icon swaps to `square.and.pencil.circle.fill`, an "Edit"
/// label slides in from the left, and the background becomes an
/// accent-colored pill. Animations respect Reduce Motion.
struct EditPillButton: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isHovered {
                    Text("Edit")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                Image(systemName: isHovered
                    ? "square.and.pencil.circle.fill"
                    : "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(isHovered ? .white : .secondary)
            }
            .padding(.horizontal, isHovered ? 8 : 5)
            .padding(.vertical, 4)
            .background(
                isHovered ? theme.accent : Color.clear,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
        }
    }
}
