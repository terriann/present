import SwiftUI
import PresentCore

struct StatItem: View {
    let title: String
    let value: String
    let icon: String?

    init(title: String, value: String, icon: String? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    var body: some View {
        VStack(spacing: Constants.spacingTight) {
            if let icon {
                Image(systemName: icon)
                    .font(.controlIconSmall)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Text(value)
                .font(.statValue)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
