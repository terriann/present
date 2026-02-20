import SwiftUI
import PresentCore

struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            Text(title)
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Constants.spacingCard)
                .padding(.top, Constants.spacingCard)
                .padding(.bottom, Constants.spacingCard)
            content
        }
    }
}
