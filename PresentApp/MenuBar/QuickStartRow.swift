import SwiftUI
import PresentCore

struct QuickStartRow: View {
    @Environment(ThemeManager.self) private var theme

    let activity: Activity
    var icon: String = "play.circle"
    var subtitle: String?
    let onTap: () -> Void
    let onEdit: () -> Void

    @State private var isRowHovered = false
    @State private var isEditHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(isRowHovered ? theme.accent : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title)
                            .font(.body)
                            .lineLimit(1)

                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.body)
                    .foregroundStyle(isEditHovered ? theme.accent : .secondary)
                    .padding(5)
                    .background(isEditHovered ? theme.accent.opacity(0.15) : Color.clear, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isEditHovered = hovering
            }
        }
        .padding(.horizontal, Constants.spacingCard)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(isRowHovered ? 0.05 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in
            isRowHovered = hovering
        }
    }
}
