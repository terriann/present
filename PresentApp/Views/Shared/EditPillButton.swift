import SwiftUI
import PresentCore

/// A compact edit button that expands into a labeled pill on hover.
///
/// Default state shows a `square.and.pencil` icon in secondary color.
/// On hover an "Edit" label slides in from the left and the background becomes a
/// subtle accent-tinted pill. Animations respect Reduce Motion.
struct EditPillButton: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.spacingTight) {
                if isHovered {
                    Text("Edit")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.accent)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                Image(systemName: "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(isHovered ? theme.accent : .secondary)
            }
            .padding(.horizontal, isHovered ? 8 : 5)
            .padding(.vertical, 4)
            .fixedSize()
            .frame(minHeight: 24)
            .background(
                isHovered ? theme.accent.opacity(0.15) : Color.clear,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAdaptiveAnimation(.easeInOut(duration: 0.35)) {
                    isHovered = hovering
                }
            }
        }
    }
}
