import SwiftUI
import PresentCore

struct QuickStartRow: View {
    let activity: Activity
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.body)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.circle")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
