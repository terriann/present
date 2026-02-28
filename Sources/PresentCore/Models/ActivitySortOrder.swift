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

/// Grouping mode for session lists in the activity breakdown card.
public enum SessionGrouping: String, CaseIterable, Sendable {
    case activity
    case none

    public var displayName: String {
        switch self {
        case .activity: "Activity"
        case .none: "None"
        }
    }
}
