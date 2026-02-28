/// Sort order for activity lists in Dashboard breakdown and Reports.
public enum ActivitySortOrder: String, CaseIterable, Sendable {
    case timeSpent
    case mostRecent
    case alphabetical

    public var displayName: String {
        switch self {
        case .timeSpent: "Time Spent"
        case .mostRecent: "Most Recent"
        case .alphabetical: "A–Z"
        }
    }
}
