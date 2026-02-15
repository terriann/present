import SwiftUI
import PresentCore

struct QuickStartRow: View {
    let activity: Activity
    let onTap: () -> Void
    let onEdit: () -> Void

    @State private var isRowHovered = false
    @State private var isEditHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle")
                        .foregroundStyle(.secondary)

                    Text(activity.title)
                        .font(.body)
                        .lineLimit(1)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(isEditHovered ? Color.accentColor : .secondary)
                    .padding(5)
                    .background(isEditHovered ? Color.accentColor.opacity(0.15) : Color.clear, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isEditHovered = hovering
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(isRowHovered ? 0.05 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in
            isRowHovered = hovering
        }
    }
}
