import SwiftUI

/// Scales content using a zoom factor while properly adjusting layout.
///
/// Uses GeometryReader to compute the available space, renders content at
/// a reduced size (for zoom > 1) or enlarged size (for zoom < 1), then
/// applies a scale effect so the result fills the original space.
///
/// This gives true "browser-style" zoom: at 1.5× you see less content
/// but everything is 50% larger. Content in ScrollViews remains scrollable.
struct ZoomContainer<Content: View>: View {
    let scale: CGFloat
    let anchor: UnitPoint
    @ViewBuilder let content: () -> Content

    init(scale: CGFloat, anchor: UnitPoint = .topLeading, @ViewBuilder content: @escaping () -> Content) {
        self.scale = scale
        self.anchor = anchor
        self.content = content
    }

    var body: some View {
        if scale == 1.0 {
            content()
        } else {
            GeometryReader { geo in
                content()
                    .frame(
                        width: geo.size.width / scale,
                        height: geo.size.height / scale
                    )
                    .scaleEffect(scale, anchor: anchor)
            }
        }
    }
}
