import Foundation

public enum SessionType: String, Codable, Sendable, CaseIterable {
    case work
    case rhythm
    case timebound
}

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case running
    case paused
    case completed
    case cancelled

    /// Terminal states shown in reports and date indicators.
    public static let closedStates: [SessionState] = [.completed, .cancelled]

    /// Raw values of `closedStates` for use in SQL queries.
    public static let closedStateRawValues: [String] = closedStates.map(\.rawValue)
}
