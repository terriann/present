import SwiftUI

/// Adds a subtle highlight background on hover for list-like rows.
///
/// The highlight uses `Color.primary` at low opacity so it adapts
/// naturally to both light and dark mode. Apply after any existing
/// background modifiers so the hover layers on top.
struct HoverHighlightModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.primary.opacity(0.10) : Color.clear)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlightModifier())
    }
}
