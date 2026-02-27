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

public struct CreateBackdatedSessionInput: Sendable {
    public var activityId: Int64
    public var sessionType: SessionType
    public var startedAt: Date
    public var endedAt: Date
    public var timerLengthMinutes: Int?
    public var breakMinutes: Int?
    public var note: String?
    public var link: String?

    public init(
        activityId: Int64,
        sessionType: SessionType = .work,
        startedAt: Date,
        endedAt: Date,
        timerLengthMinutes: Int? = nil,
        breakMinutes: Int? = nil,
        note: String? = nil,
        link: String? = nil
    ) {
        self.activityId = activityId
        self.sessionType = sessionType
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timerLengthMinutes = timerLengthMinutes
        self.breakMinutes = breakMinutes
        self.note = note
        self.link = link
    }
}

public struct UpdateSessionInput: Sendable {
    /// New note text. `nil` = no change, empty string = clear.
    public var note: String?
    /// New link URL. `nil` = no change, empty string = clear.
    public var link: String?

    public init(note: String? = nil, link: String? = nil) {
        self.note = note
        self.link = link
    }
}

// MARK: - Result Types

public enum ArchiveResult: Sendable, Equatable {
    case archived
    case promptDelete(totalSeconds: Int)
}

// MARK: - Bulk Operation Types

public enum BulkDeleteRange: String, Sendable, CaseIterable {
    case today, thisWeek, thisMonth, allTime
}

public struct BulkDeleteResult: Sendable {
    public let sessionsDeleted: Int
    public let activitiesDeleted: Int
    public let tagsDeleted: Int
    public let activeSessionCancelled: Bool

    public init(sessionsDeleted: Int = 0, activitiesDeleted: Int = 0, tagsDeleted: Int = 0, activeSessionCancelled: Bool = false) {
        self.sessionsDeleted = sessionsDeleted
        self.activitiesDeleted = activitiesDeleted
        self.tagsDeleted = tagsDeleted
        self.activeSessionCancelled = activeSessionCancelled
    }
}

// MARK: - Report Types

public struct HourlyBucket: Sendable, Equatable {
    public var hour: Int
    public var activity: Activity
    public var totalSeconds: Int

    public init(hour: Int, activity: Activity, totalSeconds: Int) {
        self.hour = hour
        self.activity = activity
        self.totalSeconds = totalSeconds
    }
}

public struct TagSummary: Sendable, Equatable {
    public var tagName: String
    public var totalSeconds: Int
    public var sessionCount: Int

    public init(tagName: String, totalSeconds: Int, sessionCount: Int) {
        self.tagName = tagName
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
    }
}

public struct TagActivitySummary: Sendable, Equatable {
    public var tagName: String
    public var activities: [ActivitySummary]
    public var totalSeconds: Int
    public var activityCount: Int

    public init(tagName: String, activities: [ActivitySummary], totalSeconds: Int, activityCount: Int) {
        self.tagName = tagName
        self.activities = activities
        self.totalSeconds = totalSeconds
        self.activityCount = activityCount
    }
}

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
    public var hourlyBreakdown: [HourlyBucket]

    public init(date: Date, totalSeconds: Int, sessionCount: Int, activities: [ActivitySummary], hourlyBreakdown: [HourlyBucket] = []) {
        self.date = date
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
        self.activities = activities
        self.hourlyBreakdown = hourlyBreakdown
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
    public var dailyBreakdown: [DailySummary]
    public var activities: [ActivitySummary]

    public init(monthOf: Date, totalSeconds: Int, sessionCount: Int, weeklyBreakdown: [WeeklySummary], dailyBreakdown: [DailySummary] = [], activities: [ActivitySummary]) {
        self.monthOf = monthOf
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
        self.weeklyBreakdown = weeklyBreakdown
        self.dailyBreakdown = dailyBreakdown
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
