import SwiftUI
import PresentCore

struct ChartCard<HeaderTrailing: View, Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let headerTrailing: HeaderTrailing
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder headerTrailing: () -> HeaderTrailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    var body: some View {
        GroupBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.cardTitle)
                    if let subtitle {
                        Text(subtitle)
                            .font(.periodHeader)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                headerTrailing
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Constants.spacingCard)
            .padding(.top, Constants.spacingCard)
            .padding(.bottom, Constants.spacingCard)
            content
        }
    }
}

extension ChartCard where HeaderTrailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, headerTrailing: { EmptyView() }, content: content)
    }
}
