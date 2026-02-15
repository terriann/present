import Foundation

// MARK: - Input Types

public struct CreateActivityInput: Sendable {
    public var title: String
    public var externalId: String?
    public var link: String?
    public var notes: String?
    public var tagIds: [Int64]

    public init(
        title: String,
        externalId: String? = nil,
        link: String? = nil,
        notes: String? = nil,
        tagIds: [Int64] = []
    ) {
        self.title = title
        self.externalId = externalId
        self.link = link
        self.notes = notes
        self.tagIds = tagIds
    }
}

public struct UpdateActivityInput: Sendable {
    public var title: String?
    public var externalId: String?
    public var link: String?
    public var notes: String?
    public var tagIds: [Int64]?

    public init(
        title: String? = nil,
        externalId: String? = nil,
        link: String? = nil,
        notes: String? = nil,
        tagIds: [Int64]? = nil
    ) {
        self.title = title
        self.externalId = externalId
        self.link = link
        self.notes = notes
        self.tagIds = tagIds
    }
}

// MARK: - Result Types

public enum ArchiveResult: Sendable, Equatable {
    case archived
    case promptDelete(totalSeconds: Int)
}

// MARK: - Report Types

public struct ActivitySummary: Sendable, Equatable {
    public var activity: Activity
    public var totalSeconds: Int
    public var sessionCount: Int

    public init(activity: Activity, totalSeconds: Int, sessionCount: Int) {
        self.activity = activity
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
    }
}

public struct DailySummary: Sendable, Equatable {
    public var date: Date
    public var totalSeconds: Int
    public var sessionCount: Int
    public var activities: [ActivitySummary]

    public init(date: Date, totalSeconds: Int, sessionCount: Int, activities: [ActivitySummary]) {
        self.date = date
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
        self.activities = activities
    }
}

public struct WeeklySummary: Sendable, Equatable {
    public var weekOf: Date
    public var totalSeconds: Int
    public var sessionCount: Int
    public var dailyBreakdown: [DailySummary]
    public var activities: [ActivitySummary]

    public init(weekOf: Date, totalSeconds: Int, sessionCount: Int, dailyBreakdown: [DailySummary], activities: [ActivitySummary]) {
        self.weekOf = weekOf
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
        self.dailyBreakdown = dailyBreakdown
        self.activities = activities
    }
}

public struct MonthlySummary: Sendable, Equatable {
    public var monthOf: Date
    public var totalSeconds: Int
    public var sessionCount: Int
    public var weeklyBreakdown: [WeeklySummary]
    public var activities: [ActivitySummary]

    public init(monthOf: Date, totalSeconds: Int, sessionCount: Int, weeklyBreakdown: [WeeklySummary], activities: [ActivitySummary]) {
        self.monthOf = monthOf
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
        self.weeklyBreakdown = weeklyBreakdown
        self.activities = activities
    }
}

public struct TodaySummary: Sendable, Equatable {
    public var totalSeconds: Int
    public var sessionCount: Int
    public var activities: [ActivitySummary]
    public var currentSession: (Session, Activity)?

    public init(totalSeconds: Int, sessionCount: Int, activities: [ActivitySummary], currentSession: (Session, Activity)? = nil) {
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
        self.activities = activities
        self.currentSession = currentSession
    }

    public static func == (lhs: TodaySummary, rhs: TodaySummary) -> Bool {
        lhs.totalSeconds == rhs.totalSeconds
        && lhs.sessionCount == rhs.sessionCount
        && lhs.activities == rhs.activities
    }
}
