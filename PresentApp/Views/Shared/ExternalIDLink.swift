import SwiftUI
import PresentCore

struct ExternalIDLink: View {
    let activity: Activity
    let baseUrl: String

    var body: some View {
        if let externalId = activity.externalId, !externalId.isEmpty {
            if let url = resolvedURL {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text(externalId)
                    }
                    .font(.caption)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                    Text(externalId)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else if let link = activity.link, let url = URL(string: link) {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text(link)
                        .lineLimit(1)
                }
                .font(.caption)
            }
        }
    }

    private var resolvedURL: URL? {
        guard let externalId = activity.externalId, !externalId.isEmpty else { return nil }
        guard !baseUrl.isEmpty else { return nil }
        return URL(string: baseUrl + externalId)
    }
}
