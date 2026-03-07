import SwiftUI
import PresentCore

struct QuickStartRow: View {
    @Environment(ThemeManager.self) private var theme

    let activity: Activity
    var icon: String = "play.circle"
    var subtitle: String?
    var isSelected: Bool = false
    let onTap: () -> Void
    let onEdit: () -> Void

    @State private var isRowHovered = false

    private var filledIcon: String {
        icon.hasSuffix(".fill") ? icon : "\(icon).fill"
    }

    var body: some View {
        HStack(spacing: Constants.spacingCompact) {
            Button(action: onTap) {
                HStack(spacing: Constants.spacingCompact) {
                    Image(systemName: isSelected || isRowHovered ? filledIcon : icon)
                        .foregroundStyle(isSelected || isRowHovered ? theme.accent : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Constants.spacingTight) {
                            Text(activity.title)
                                .font(.body)
                                .lineLimit(1)

                            if activity.isSystem {
                                Text("System")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

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

            EditPillButton(action: onEdit)
        }
        .padding(.horizontal, Constants.spacingCard)
        .padding(.vertical, 6)
        .background(isSelected ? theme.accent.opacity(0.12) : Color.primary.opacity(isRowHovered ? 0.05 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in
            isRowHovered = hovering
        }
    }
}
