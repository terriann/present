import SwiftUI

/// Floating tooltip card for bar chart hover.
struct ChartTooltip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            content
        }
        .padding(8)
        .frame(maxWidth: 180)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .allowsHitTesting(false)
    }
}

/// Centered tooltip displayed in the donut hole on hover.
struct DonutCenterTooltip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 2) {
            content
        }
        .frame(maxWidth: 100)
        .allowsHitTesting(false)
    }
}
