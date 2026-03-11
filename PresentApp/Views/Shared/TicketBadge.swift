import SwiftUI
import PresentCore

/// Capsule badge showing a ticket ID or link hostname, opening the URL on click.
struct TicketBadge: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.openURL) private var openURL

    let ticketId: String?
    let link: String?
    var font: Font = .caption
    var scale: CGFloat = 1.0
    var tint: Color?

    /// Resolved tint color — uses the override if provided, otherwise the theme accent.
    private var resolvedTint: Color {
        tint ?? theme.accent
    }

    var body: some View {
        if let ticketId, let link, let url = URL(string: link) {
            Button {
                openURL(url)
            } label: {
                Text(ticketId)
                    .font(font)
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(resolvedTint.opacity(0.12), in: Capsule())
                    .foregroundStyle(resolvedTint)
            }
            .buttonStyle(.plain)
            .help(link)
        } else if let link, let url = URL(string: link) {
            Button {
                openURL(url)
            } label: {
                Text(url.host ?? link)
                    .font(font)
                    .lineLimit(1)
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(resolvedTint.opacity(0.12), in: Capsule())
                    .foregroundStyle(resolvedTint)
            }
            .buttonStyle(.plain)
            .help(link)
        }
    }
}
