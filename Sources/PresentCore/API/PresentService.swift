import Foundation
import GRDB

public enum PresentError: Error, LocalizedError, Sendable {
    case activityNotFound(Int64)
    case tagNotFound(Int64)
    case sessionNotFound
    case noActiveSession
    case sessionAlreadyActive
    case sessionNotPaused
    case sessionAlreadyPaused
    case activityLimitReached(max: Int)
    case activityIsArchived(Int64)
    case invalidInput(String)
    case cannotDeleteActiveActivity

    public var errorDescription: String? {
        switch self {
        case .activityNotFound(let id): "Activity \(id) not found."
        case .tagNotFound(let id): "Tag \(id) not found."
        case .sessionNotFound: "Session not found."
        case .noActiveSession: "No active session."
        case .sessionAlreadyActive: "A session is already active. Stop it first."
        case .sessionNotPaused: "Session is not paused."
        case .sessionAlreadyPaused: "Session is already paused."
        case .activityLimitReached(let max): "Active activity limit reached (\(max)). Archive or delete activities first."
        case .activityIsArchived(let id): "Activity \(id) is archived and cannot be used for new sessions."
        case .invalidInput(let msg): msg
        case .cannotDeleteActiveActivity: "Cannot delete an activity with an active session."
        }
    }
}

public final class PresentService: PresentAPI, Sendable {
    private let dbWriter: any DatabaseWriter
    public static let maxActiveActivities = 50

    public init(databasePool: any DatabaseWriter) {
        self.dbWriter = databasePool
    }

    // MARK: - Sessions

    public func startSession(activityId: Int64, type: SessionType, timerMinutes: Int? = nil, plannedStart: Date? = nil, plannedEnd: Date? = nil) async throws -> Session {
        try await dbWriter.write { db in
            // Check no active session
            let active = try Session
                .filter(Session.Columns.state == SessionState.running.rawValue || Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db)
            if active != nil {
                throw PresentError.sessionAlreadyActive
            }

            // Check activity exists and is not archived
            guard let activity = try Activity.fetchOne(db, key: activityId) else {
                throw PresentError.activityNotFound(activityId)
            }
            if activity.isArchived {
                throw PresentError.activityIsArchived(activityId)
            }

            let now = Date()
            var session = Session(
                activityId: activityId,
                sessionType: type,
                startedAt: now,
                plannedStart: plannedStart,
                plannedEnd: plannedEnd,
                timerLengthMinutes: timerMinutes,
                state: .running,
                createdAt: now
            )

            // For rhythm sessions, determine the session index
            if type == .rhythm {
                let lastRhythm = try Session
                    .filter(Session.Columns.sessionType == SessionType.rhythm.rawValue)
                    .filter(Session.Columns.state == SessionState.completed.rawValue)
                    .order(Session.Columns.id.desc)
                    .fetchOne(db)

                let lastIndex = lastRhythm?.rhythmSessionIndex ?? 0
                session.rhythmSessionIndex = (lastIndex % 4) + 1
            }

            try session.insert(db)
            session.id = db.lastInsertedRowID
            return session
        }
    }

    public func pauseSession() async throws -> Session {
        try await dbWriter.write { db in
            guard var session = try Session
                .filter(Session.Columns.state == SessionState.running.rawValue)
                .fetchOne(db) else {
                throw PresentError.noActiveSession
            }

            session.state = .paused
            session.lastPausedAt = Date()
            try session.update(db)
            return session
        }
    }

    public func resumeSession() async throws -> Session {
        try await dbWriter.write { db in
            guard var session = try Session
                .filter(Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db) else {
                throw PresentError.sessionNotPaused
            }

            let now = Date()
            if let pausedAt = session.lastPausedAt {
                let pauseDuration = Int(now.timeIntervalSince(pausedAt))
                session.totalPausedSeconds += pauseDuration
            }
            session.state = .running
            session.lastPausedAt = nil
            try session.update(db)
            return session
        }
    }

    public func stopSession() async throws -> Session {
        try await dbWriter.write { db in
            guard var session = try Session
                .filter(Session.Columns.state == SessionState.running.rawValue || Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db) else {
                throw PresentError.noActiveSession
            }

            let now = Date()

            // If paused, accumulate remaining pause time
            if session.state == .paused, let pausedAt = session.lastPausedAt {
                let pauseDuration = Int(now.timeIntervalSince(pausedAt))
                session.totalPausedSeconds += pauseDuration
            }

            session.state = .completed
            session.endedAt = now
            session.lastPausedAt = nil

            let totalElapsed = Int(now.timeIntervalSince(session.startedAt))
            session.durationSeconds = max(0, totalElapsed - session.totalPausedSeconds)

            try session.update(db)
            return session
        }
    }

    public func cancelSession() async throws {
        try await dbWriter.write { db in
            guard var session = try Session
                .filter(Session.Columns.state == SessionState.running.rawValue || Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db) else {
                throw PresentError.noActiveSession
            }

            session.state = .cancelled
            session.endedAt = Date()
            session.durationSeconds = 0
            try session.update(db)
        }
    }

    public func currentSession() async throws -> (Session, Activity)? {
        try await dbWriter.read { db in
            guard let session = try Session
                .filter(Session.Columns.state == SessionState.running.rawValue || Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db) else {
                return nil
            }
            guard let activity = try Activity.fetchOne(db, key: session.activityId) else {
                return nil
            }
            return (session, activity)
        }
    }

    // MARK: - Activities

    public func createActivity(_ input: CreateActivityInput) async throws -> Activity {
        guard !input.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PresentError.invalidInput("Activity title cannot be empty.")
        }

        return try await dbWriter.write { db in
            let activeCount = try Activity.filter(Activity.Columns.isArchived == false).fetchCount(db)
            if activeCount >= PresentService.maxActiveActivities {
                throw PresentError.activityLimitReached(max: PresentService.maxActiveActivities)
            }

            let now = Date()
            var activity = Activity(
                title: input.title.trimmingCharacters(in: .whitespaces),
                externalId: input.externalId,
                link: input.link,
                notes: input.notes,
                createdAt: now,
                updatedAt: now
            )
            try activity.insert(db)
            activity.id = db.lastInsertedRowID

            for tagId in input.tagIds {
                guard try Tag.fetchOne(db, key: tagId) != nil else {
                    throw PresentError.tagNotFound(tagId)
                }
                try ActivityTag(activityId: activity.id!, tagId: tagId).insert(db)
            }

            return activity
        }
    }

    public func updateActivity(id: Int64, _ input: UpdateActivityInput) async throws -> Activity {
        try await dbWriter.write { db in
            guard var activity = try Activity.fetchOne(db, key: id) else {
                throw PresentError.activityNotFound(id)
            }

            if let title = input.title {
                guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw PresentError.invalidInput("Activity title cannot be empty.")
                }
                activity.title = title.trimmingCharacters(in: .whitespaces)
            }
            if let externalId = input.externalId {
                activity.externalId = externalId.isEmpty ? nil : externalId
            }
            if let link = input.link {
                activity.link = link.isEmpty ? nil : link
            }
            if let notes = input.notes {
                activity.notes = notes.isEmpty ? nil : notes
            }
            activity.updatedAt = Date()
            try activity.update(db)

            if let tagIds = input.tagIds {
                try ActivityTag.filter(ActivityTag.Columns.activityId == id).deleteAll(db)
                for tagId in tagIds {
                    guard try Tag.fetchOne(db, key: tagId) != nil else {
                        throw PresentError.tagNotFound(tagId)
                    }
                    try ActivityTag(activityId: id, tagId: tagId).insert(db)
                }
            }

            return activity
        }
    }

    public func archiveActivity(id: Int64) async throws -> ArchiveResult {
        try await dbWriter.write { db in
            guard var activity = try Activity.fetchOne(db, key: id) else {
                throw PresentError.activityNotFound(id)
            }

            // Check if there's an active session for this activity
            let activeSession = try Session
                .filter(Session.Columns.activityId == id)
                .filter(Session.Columns.state == SessionState.running.rawValue || Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db)
            if activeSession != nil {
                throw PresentError.cannotDeleteActiveActivity
            }

            // Calculate total tracked time
            let totalSeconds = try Int.fetchOne(db,
                sql: "SELECT COALESCE(SUM(durationSeconds), 0) FROM session WHERE activityId = ? AND state = ?",
                arguments: [id, SessionState.completed.rawValue]
            ) ?? 0

            if totalSeconds < 600 { // < 10 minutes
                return .promptDelete(totalSeconds: totalSeconds)
            }

            activity.isArchived = true
            activity.updatedAt = Date()
            try activity.update(db)
            return .archived
        }
    }

    public func deleteActivity(id: Int64) async throws {
        try await dbWriter.write { db in
            guard let activity = try Activity.fetchOne(db, key: id) else {
                throw PresentError.activityNotFound(id)
            }

            // Check if there's an active session for this activity
            let activeSession = try Session
                .filter(Session.Columns.activityId == id)
                .filter(Session.Columns.state == SessionState.running.rawValue || Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db)
            if activeSession != nil {
                throw PresentError.cannotDeleteActiveActivity
            }

            // Delete associated sessions
            try Session.filter(Session.Columns.activityId == id).deleteAll(db)
            try activity.delete(db)
        }
    }

    public func unarchiveActivity(id: Int64) async throws -> Activity {
        try await dbWriter.write { db in
            guard var activity = try Activity.fetchOne(db, key: id) else {
                throw PresentError.activityNotFound(id)
            }

            let activeCount = try Activity.filter(Activity.Columns.isArchived == false).fetchCount(db)
            if activeCount >= PresentService.maxActiveActivities {
                throw PresentError.activityLimitReached(max: PresentService.maxActiveActivities)
            }

            activity.isArchived = false
            activity.updatedAt = Date()
            try activity.update(db)
            return activity
        }
    }

    public func listActivities(includeArchived: Bool) async throws -> [Activity] {
        try await dbWriter.read { db in
            if includeArchived {
                return try Activity.order(Activity.Columns.updatedAt.desc).fetchAll(db)
            } else {
                return try Activity
                    .filter(Activity.Columns.isArchived == false)
                    .order(Activity.Columns.updatedAt.desc)
                    .fetchAll(db)
            }
        }
    }

    public func getActivity(id: Int64) async throws -> Activity {
        try await dbWriter.read { db in
            guard let activity = try Activity.fetchOne(db, key: id) else {
                throw PresentError.activityNotFound(id)
            }
            return activity
        }
    }

    public func searchActivities(query: String) async throws -> [Activity] {
        let sanitized = query.trimmingCharacters(in: .whitespaces)
        guard !sanitized.isEmpty else { return [] }

        return try await dbWriter.read { db in
            let pattern = FTS5Pattern(matchingAnyTokenIn: sanitized)
            guard let pattern else { return [] }

            let sql = """
                SELECT a.*
                FROM activity a
                INNER JOIN activity_fts fts ON fts.rowid = a.id
                WHERE activity_fts MATCH ?
                ORDER BY rank
                """
            return try Activity.fetchAll(db, sql: sql, arguments: [pattern.rawPattern])
        }
    }

    public func recentActivities(limit: Int) async throws -> [Activity] {
        try await dbWriter.read { db in
            // Get activities that have recent sessions, ordered by most recent session
            let sql = """
                SELECT DISTINCT a.*
                FROM activity a
                INNER JOIN session s ON s.activityId = a.id
                WHERE a.isArchived = 0
                ORDER BY s.startedAt DESC
                LIMIT ?
                """
            return try Activity.fetchAll(db, sql: sql, arguments: [limit])
        }
    }

    // MARK: - Notes

    public func appendNote(activityId: Int64, text: String) async throws -> Activity {
        try await dbWriter.write { db in
            guard var activity = try Activity.fetchOne(db, key: activityId) else {
                throw PresentError.activityNotFound(activityId)
            }

            if let existing = activity.notes, !existing.isEmpty {
                activity.notes = existing + "\n" + text
            } else {
                activity.notes = text
            }
            activity.updatedAt = Date()
            try activity.update(db)
            return activity
        }
    }

    // MARK: - Tags

    public func createTag(name: String) async throws -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw PresentError.invalidInput("Tag name cannot be empty.")
        }

        return try await dbWriter.write { db in
            var tag = Tag(name: trimmed)
            try tag.insert(db)
            tag.id = db.lastInsertedRowID
            return tag
        }
    }

    public func deleteTag(id: Int64) async throws {
        try await dbWriter.write { db in
            guard let tag = try Tag.fetchOne(db, key: id) else {
                throw PresentError.tagNotFound(id)
            }
            try tag.delete(db)
        }
    }

    public func listTags() async throws -> [Tag] {
        try await dbWriter.read { db in
            try Tag.order(Tag.Columns.name).fetchAll(db)
        }
    }

    public func tagActivity(activityId: Int64, tagId: Int64) async throws {
        try await dbWriter.write { db in
            guard try Activity.fetchOne(db, key: activityId) != nil else {
                throw PresentError.activityNotFound(activityId)
            }
            guard try Tag.fetchOne(db, key: tagId) != nil else {
                throw PresentError.tagNotFound(tagId)
            }
            try ActivityTag(activityId: activityId, tagId: tagId).insert(db)
        }
    }

    public func untagActivity(activityId: Int64, tagId: Int64) async throws {
        try await dbWriter.write { db in
            try ActivityTag
                .filter(ActivityTag.Columns.activityId == activityId && ActivityTag.Columns.tagId == tagId)
                .deleteAll(db)
        }
    }

    // MARK: - Reports

    public func dailySummary(date: Date, includeArchived: Bool) async throws -> DailySummary {
        try await dbWriter.read { db in
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

            let archiveFilter = includeArchived ? "" : " AND a.isArchived = 0"
            let sql = """
                SELECT a.*, COALESCE(SUM(s.durationSeconds), 0) as totalSecs, COUNT(s.id) as sessCount
                FROM activity a
                INNER JOIN session s ON s.activityId = a.id
                WHERE s.state = ?
                  AND s.startedAt >= ? AND s.startedAt < ?
                  \(archiveFilter)
                GROUP BY a.id
                ORDER BY totalSecs DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [
                SessionState.completed.rawValue,
                startOfDay, endOfDay
            ])

            var activities: [ActivitySummary] = []
            var totalSeconds = 0
            var totalSessions = 0

            for row in rows {
                let activity = try Activity(row: row)
                let secs: Int = row["totalSecs"]
                let count: Int = row["sessCount"]
                activities.append(ActivitySummary(activity: activity, totalSeconds: secs, sessionCount: count))
                totalSeconds += secs
                totalSessions += count
            }

            return DailySummary(date: startOfDay, totalSeconds: totalSeconds, sessionCount: totalSessions, activities: activities)
        }
    }

    public func weeklySummary(weekOf: Date, includeArchived: Bool) async throws -> WeeklySummary {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: weekOf)!.start
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!

        var dailyBreakdown: [DailySummary] = []
        var current = startOfWeek
        while current < endOfWeek {
            let daily = try await dailySummary(date: current, includeArchived: includeArchived)
            dailyBreakdown.append(daily)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        // Aggregate activity summaries across the week
        var activityMap: [Int64: ActivitySummary] = [:]
        var totalSeconds = 0
        var totalSessions = 0

        for daily in dailyBreakdown {
            totalSeconds += daily.totalSeconds
            totalSessions += daily.sessionCount
            for actSummary in daily.activities {
                if var existing = activityMap[actSummary.activity.id!] {
                    existing.totalSeconds += actSummary.totalSeconds
                    existing.sessionCount += actSummary.sessionCount
                    activityMap[actSummary.activity.id!] = existing
                } else {
                    activityMap[actSummary.activity.id!] = actSummary
                }
            }
        }

        let activities = activityMap.values.sorted { $0.totalSeconds > $1.totalSeconds }
        return WeeklySummary(weekOf: startOfWeek, totalSeconds: totalSeconds, sessionCount: totalSessions, dailyBreakdown: dailyBreakdown, activities: activities)
    }

    public func monthlySummary(monthOf: Date, includeArchived: Bool) async throws -> MonthlySummary {
        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: monthOf)!.start
        let endOfMonth = calendar.dateInterval(of: .month, for: monthOf)!.end

        // Get weekly summaries for all weeks that overlap this month
        var weeklyBreakdown: [WeeklySummary] = []
        var current = startOfMonth
        var seenWeeks: Set<Date> = []

        while current < endOfMonth {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: current)!.start
            if !seenWeeks.contains(weekStart) {
                seenWeeks.insert(weekStart)
                let weekly = try await weeklySummary(weekOf: current, includeArchived: includeArchived)
                weeklyBreakdown.append(weekly)
            }
            current = calendar.date(byAdding: .day, value: 7, to: current)!
        }

        // Aggregate
        var activityMap: [Int64: ActivitySummary] = [:]
        var totalSeconds = 0
        var totalSessions = 0

        for weekly in weeklyBreakdown {
            totalSeconds += weekly.totalSeconds
            totalSessions += weekly.sessionCount
            for actSummary in weekly.activities {
                if var existing = activityMap[actSummary.activity.id!] {
                    existing.totalSeconds += actSummary.totalSeconds
                    existing.sessionCount += actSummary.sessionCount
                    activityMap[actSummary.activity.id!] = existing
                } else {
                    activityMap[actSummary.activity.id!] = actSummary
                }
            }
        }

        let activities = activityMap.values.sorted { $0.totalSeconds > $1.totalSeconds }
        return MonthlySummary(monthOf: startOfMonth, totalSeconds: totalSeconds, sessionCount: totalSessions, weeklyBreakdown: weeklyBreakdown, activities: activities)
    }

    public func exportCSV(from: Date, to: Date, includeArchived: Bool) async throws -> Data {
        try await dbWriter.read { db in
            let archiveFilter = includeArchived ? "" : " AND a.isArchived = 0"
            let sql = """
                SELECT s.id, a.title, s.sessionType, s.startedAt, s.endedAt, s.durationSeconds, s.state
                FROM session s
                INNER JOIN activity a ON a.id = s.activityId
                WHERE s.startedAt >= ? AND s.startedAt <= ?
                  AND s.state = ?
                  \(archiveFilter)
                ORDER BY s.startedAt ASC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [from, to, SessionState.completed.rawValue])
            return CSVExporter.export(rows: rows)
        }
    }

    // MARK: - Preferences

    public func getPreference(key: String) async throws -> String? {
        try await dbWriter.read { db in
            try Preference.fetchOne(db, key: key)?.value
        }
    }

    public func setPreference(key: String, value: String) async throws {
        try await dbWriter.write { db in
            var pref = Preference(key: key, value: value)
            try pref.save(db)
        }
    }

    // MARK: - Status

    public func todaySummary() async throws -> TodaySummary {
        let daily = try await dailySummary(date: Date(), includeArchived: false)
        let current = try await currentSession()
        return TodaySummary(
            totalSeconds: daily.totalSeconds,
            sessionCount: daily.sessionCount,
            activities: daily.activities,
            currentSession: current
        )
    }
}
