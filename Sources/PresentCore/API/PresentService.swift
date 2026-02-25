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
    case cannotDeleteActiveSession
    case sessionOverlap
    case cannotModifySystemActivity
    case rhythmNotAllowedForSystemActivity

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
        case .cannotDeleteActiveSession: "Active sessions must be stopped before they can be deleted."
        case .sessionOverlap: "Session overlaps with an existing session."
        case .cannotModifySystemActivity: "System activities cannot be modified or deleted."
        case .rhythmNotAllowedForSystemActivity: "Rhythm sessions cannot be started on system activities. Use a work or timebound session instead."
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

    public func startSession(activityId: Int64, type: SessionType, timerMinutes: Int? = nil, breakMinutes: Int? = nil) async throws -> Session {
        if let timerMinutes {
            try Validation.validateRange(timerMinutes, range: Constants.sessionMinutesRange, fieldName: "Timer duration")
        }
        if let breakMinutes {
            try Validation.validateRange(breakMinutes, range: Constants.breakDurationRange, fieldName: "Break duration")
        }

        return try await dbWriter.write { db in
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
            if activity.isSystem && type == .rhythm {
                throw PresentError.rhythmNotAllowedForSystemActivity
            }

            let now = Date()
            var session = Session(
                activityId: activityId,
                sessionType: type,
                startedAt: now,
                timerLengthMinutes: timerMinutes,
                state: .running,
                createdAt: now
            )

            // For rhythm sessions, store break duration and determine the session index
            if type == .rhythm {
                session.breakMinutes = breakMinutes

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

            // Open the first segment
            let segment = SessionSegment(sessionId: session.id!, startedAt: now)
            try segment.insert(db)

            return session
        }
    }

    public func createBackdatedSession(_ input: CreateBackdatedSessionInput) async throws -> Session {
        // Validate endedAt > startedAt
        guard input.endedAt > input.startedAt else {
            throw PresentError.invalidInput("End time must be after start time.")
        }

        // Validate startedAt not in the future
        guard input.startedAt <= Date() else {
            throw PresentError.invalidInput("Start time cannot be in the future.")
        }

        if let timerMinutes = input.timerLengthMinutes {
            try Validation.validateRange(timerMinutes, range: Constants.sessionMinutesRange, fieldName: "Timer duration")
        }
        if let breakMinutes = input.breakMinutes {
            try Validation.validateRange(breakMinutes, range: Constants.breakDurationRange, fieldName: "Break duration")
        }

        return try await dbWriter.write { db in
            // Validate activity exists and is not archived
            guard let activity = try Activity.fetchOne(db, key: input.activityId) else {
                throw PresentError.activityNotFound(input.activityId)
            }
            if activity.isArchived {
                throw PresentError.activityIsArchived(input.activityId)
            }

            // Overlap check: completed sessions
            let overlapSQL = """
                SELECT COUNT(*) FROM session
                WHERE state = ?
                  AND startedAt < ? AND endedAt > ?
                """
            let overlapCount = try Int.fetchOne(db, sql: overlapSQL, arguments: [
                SessionState.completed.rawValue,
                input.endedAt, input.startedAt
            ]) ?? 0
            if overlapCount > 0 {
                throw PresentError.sessionOverlap
            }

            // Overlap check: active (running/paused) sessions
            let activeSQL = """
                SELECT COUNT(*) FROM session
                WHERE state IN (?, ?)
                  AND startedAt < ?
                """
            let activeOverlap = try Int.fetchOne(db, sql: activeSQL, arguments: [
                SessionState.running.rawValue, SessionState.paused.rawValue,
                input.endedAt
            ]) ?? 0
            if activeOverlap > 0 {
                throw PresentError.sessionOverlap
            }

            let durationSeconds = Int(input.endedAt.timeIntervalSince(input.startedAt))
            let now = Date()
            var session = Session(
                activityId: input.activityId,
                sessionType: input.sessionType,
                startedAt: input.startedAt,
                endedAt: input.endedAt,
                durationSeconds: durationSeconds,
                timerLengthMinutes: input.timerLengthMinutes,
                state: .completed,
                breakMinutes: input.breakMinutes,
                createdAt: now
            )

            try session.insert(db)
            session.id = db.lastInsertedRowID

            // Insert single closed segment representing the full active duration
            let segment = SessionSegment(sessionId: session.id!, startedAt: input.startedAt, endedAt: input.endedAt)
            try segment.insert(db)

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

            let now = Date()
            session.state = .paused
            session.lastPausedAt = now
            try session.update(db)

            // Close the open segment
            if var openSegment = try SessionSegment
                .filter(SessionSegment.Columns.sessionId == session.id!)
                .filter(SessionSegment.Columns.endedAt == nil)
                .fetchOne(db) {
                openSegment.endedAt = now
                try openSegment.update(db)
            }

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

            // Open a new segment
            let segment = SessionSegment(sessionId: session.id!, startedAt: now)
            try segment.insert(db)

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

            // If running, close the open segment
            if session.state == .running,
               var openSegment = try SessionSegment
                .filter(SessionSegment.Columns.sessionId == session.id!)
                .filter(SessionSegment.Columns.endedAt == nil)
                .fetchOne(db) {
                openSegment.endedAt = now
                try openSegment.update(db)
            }

            session.state = .completed
            session.endedAt = now
            session.lastPausedAt = nil

            // Compute duration from sum of all closed segments
            let segments = try SessionSegment
                .filter(SessionSegment.Columns.sessionId == session.id!)
                .filter(SessionSegment.Columns.endedAt != nil)
                .fetchAll(db)
            let activeDuration = segments.reduce(0) { sum, seg in
                guard let end = seg.endedAt else { return sum }
                return sum + Int(end.timeIntervalSince(seg.startedAt))
            }
            session.durationSeconds = max(0, activeDuration)

            try session.update(db)
            return session
        }
    }

    public func cancelSession() async throws {
        try await dbWriter.write { db in
            guard let session = try Session
                .filter(Session.Columns.state == SessionState.running.rawValue || Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db) else {
                throw PresentError.noActiveSession
            }

            try session.delete(db)
        }
    }

    public func deleteSession(id: Int64) async throws {
        try await dbWriter.write { db in
            guard let session = try Session.fetchOne(db, key: id) else {
                throw PresentError.sessionNotFound
            }
            if session.state == .running || session.state == .paused {
                throw PresentError.cannotDeleteActiveSession
            }
            try session.delete(db)
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

    public func listSessions(from startDate: Date, to endDate: Date, type: SessionType? = nil, activityId: Int64? = nil, includeArchived: Bool = true) async throws -> [(Session, Activity)] {
        try await dbWriter.read { db in
            // Overlap: session started before range end AND ended after range start (or still running)
            var conditions = ["s.startedAt < ?", "(s.endedAt > ? OR s.endedAt IS NULL)", "s.state IN (?, ?)"]
            var arguments: [any DatabaseValueConvertible] = [endDate, startDate, SessionState.completed.rawValue, SessionState.cancelled.rawValue]

            if let type {
                conditions.append("s.sessionType = ?")
                arguments.append(type.rawValue)
            }
            if let activityId {
                conditions.append("s.activityId = ?")
                arguments.append(activityId)
            }
            if !includeArchived {
                conditions.append("a.isArchived = 0")
            }

            let sql = """
                SELECT s.*, a.id AS a_id, a.title AS a_title, a.externalId AS a_externalId,
                       a.link AS a_link, a.notes AS a_notes, a.isArchived AS a_isArchived,
                       a.isSystem AS a_isSystem, a.createdAt AS a_createdAt, a.updatedAt AS a_updatedAt
                FROM session s
                INNER JOIN activity a ON a.id = s.activityId
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY s.startedAt DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return rows.map { row in
                let session = try! Session(row: row)
                let activity = Activity(
                    id: row["a_id"],
                    title: row["a_title"],
                    externalId: row["a_externalId"],
                    link: row["a_link"],
                    notes: row["a_notes"],
                    isArchived: row["a_isArchived"],
                    isSystem: row["a_isSystem"],
                    createdAt: row["a_createdAt"],
                    updatedAt: row["a_updatedAt"]
                )
                return (session, activity)
            }
        }
    }

    public func getSession(id: Int64) async throws -> (Session, Activity) {
        try await dbWriter.read { db in
            let sql = """
                SELECT s.*, a.id AS a_id, a.title AS a_title, a.externalId AS a_externalId,
                       a.link AS a_link, a.notes AS a_notes, a.isArchived AS a_isArchived,
                       a.isSystem AS a_isSystem, a.createdAt AS a_createdAt, a.updatedAt AS a_updatedAt
                FROM session s
                INNER JOIN activity a ON a.id = s.activityId
                WHERE s.id = ?
                """

            guard let row = try Row.fetchOne(db, sql: sql, arguments: [id]) else {
                throw PresentError.sessionNotFound
            }

            let session = try Session(row: row)
            let activity = Activity(
                id: row["a_id"],
                title: row["a_title"],
                externalId: row["a_externalId"],
                link: row["a_link"],
                notes: row["a_notes"],
                isArchived: row["a_isArchived"],
                createdAt: row["a_createdAt"],
                updatedAt: row["a_updatedAt"]
            )
            return (session, activity)
        }
    }

    public func lastCompletedSession(since: Date) async throws -> (Session, Activity)? {
        try await dbWriter.read { db in
            let sql = """
                SELECT s.*, a.id AS a_id, a.title AS a_title, a.externalId AS a_externalId,
                       a.link AS a_link, a.notes AS a_notes, a.isArchived AS a_isArchived,
                       a.isSystem AS a_isSystem, a.createdAt AS a_createdAt, a.updatedAt AS a_updatedAt
                FROM session s
                INNER JOIN activity a ON a.id = s.activityId
                WHERE s.state = ? AND s.endedAt >= ? AND a.isArchived = 0
                ORDER BY s.endedAt DESC
                LIMIT 1
                """

            guard let row = try Row.fetchOne(db, sql: sql, arguments: [
                SessionState.completed.rawValue, since
            ]) else {
                return nil
            }

            let session = try Session(row: row)
            let activity = Activity(
                id: row["a_id"],
                title: row["a_title"],
                externalId: row["a_externalId"],
                link: row["a_link"],
                notes: row["a_notes"],
                isArchived: row["a_isArchived"],
                createdAt: row["a_createdAt"],
                updatedAt: row["a_updatedAt"]
            )
            return (session, activity)
        }
    }

    public func lastCompletedNonSystemSession(since: Date) async throws -> (Session, Activity)? {
        try await dbWriter.read { db in
            let sql = """
                SELECT s.*, a.id AS a_id, a.title AS a_title, a.externalId AS a_externalId,
                       a.link AS a_link, a.notes AS a_notes, a.isArchived AS a_isArchived,
                       a.isSystem AS a_isSystem, a.createdAt AS a_createdAt, a.updatedAt AS a_updatedAt
                FROM session s
                INNER JOIN activity a ON a.id = s.activityId
                WHERE s.state = ? AND s.endedAt >= ? AND a.isArchived = 0 AND a.isSystem = 0
                ORDER BY s.endedAt DESC
                LIMIT 1
                """

            guard let row = try Row.fetchOne(db, sql: sql, arguments: [
                SessionState.completed.rawValue, since
            ]) else {
                return nil
            }

            let session = try Session(row: row)
            let activity = Activity(
                id: row["a_id"],
                title: row["a_title"],
                externalId: row["a_externalId"],
                link: row["a_link"],
                notes: row["a_notes"],
                isArchived: row["a_isArchived"],
                createdAt: row["a_createdAt"],
                updatedAt: row["a_updatedAt"]
            )
            return (session, activity)
        }
    }

    public func earliestSessionDate() async throws -> Date? {
        try await dbWriter.read { db in
            try Date.fetchOne(db,
                sql: "SELECT MIN(startedAt) FROM session WHERE state = ?",
                arguments: [SessionState.completed.rawValue]
            )
        }
    }

    // MARK: - Activities

    public func createActivity(_ input: CreateActivityInput) async throws -> Activity {
        let title = try Validation.sanitize(input.title, fieldName: "Activity title", maxLength: Constants.maxTitleLength)
        let externalId = try Validation.sanitizeOptional(input.externalId, fieldName: "External ID", maxLength: Constants.maxExternalIdLength)
        let notes = try Validation.sanitizeOptional(input.notes, fieldName: "Notes", maxLength: Constants.maxNotesLength)

        if let link = input.link, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try Validation.validateLink(link)
        }
        let link = try Validation.sanitizeOptional(input.link, fieldName: "Link", maxLength: Constants.maxLinkLength)

        return try await dbWriter.write { db in
            let activeCount = try Activity
                .filter(Activity.Columns.isArchived == false)
                .filter(Activity.Columns.isSystem == false)
                .fetchCount(db)
            if activeCount >= PresentService.maxActiveActivities {
                throw PresentError.activityLimitReached(max: PresentService.maxActiveActivities)
            }

            let now = Date()
            var activity = Activity(
                title: title,
                externalId: externalId,
                link: link,
                notes: notes,
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
        // Validate inputs before entering the database write
        let validatedTitle: String? = if let title = input.title {
            try Validation.sanitize(title, fieldName: "Activity title", maxLength: Constants.maxTitleLength)
        } else {
            nil
        }
        if let link = input.link, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try Validation.validateLink(link)
        }
        let validatedExternalId: String?? = if let externalId = input.externalId {
            try Validation.sanitizeOptional(externalId, fieldName: "External ID", maxLength: Constants.maxExternalIdLength)
        } else {
            nil as String??
        }
        let validatedLink: String?? = if let link = input.link {
            try Validation.sanitizeOptional(link, fieldName: "Link", maxLength: Constants.maxLinkLength)
        } else {
            nil as String??
        }
        let validatedNotes: String?? = if let notes = input.notes {
            try Validation.sanitizeOptional(notes, fieldName: "Notes", maxLength: Constants.maxNotesLength)
        } else {
            nil as String??
        }

        return try await dbWriter.write { db in
            guard var activity = try Activity.fetchOne(db, key: id) else {
                throw PresentError.activityNotFound(id)
            }
            if activity.isSystem {
                throw PresentError.cannotModifySystemActivity
            }

            if let title = validatedTitle {
                activity.title = title
            }
            if let externalId = validatedExternalId {
                activity.externalId = externalId
            }
            if let link = validatedLink {
                activity.link = link
            }
            if let notes = validatedNotes {
                activity.notes = notes
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
            if activity.isSystem {
                throw PresentError.cannotModifySystemActivity
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
            if activity.isSystem {
                throw PresentError.cannotModifySystemActivity
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

            let activeCount = try Activity
                .filter(Activity.Columns.isArchived == false)
                .filter(Activity.Columns.isSystem == false)
                .fetchCount(db)
            if activeCount >= PresentService.maxActiveActivities {
                throw PresentError.activityLimitReached(max: PresentService.maxActiveActivities)
            }

            activity.isArchived = false
            activity.updatedAt = Date()
            try activity.update(db)
            return activity
        }
    }

    public func listActivities(includeArchived: Bool, includeSystem: Bool) async throws -> [Activity] {
        try await dbWriter.read { db in
            var request = Activity.all()

            if !includeArchived {
                request = request.filter(Activity.Columns.isArchived == false)
            }
            if !includeSystem {
                request = request.filter(Activity.Columns.isSystem == false)
            }

            if includeSystem {
                // System activities sort first, then alphabetical
                request = request.order(Activity.Columns.isSystem.desc, Activity.Columns.title.asc)
            } else {
                request = request.order(Activity.Columns.title.asc)
            }

            return try request.fetchAll(db)
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
        let sanitized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return [] }

        if sanitized.count > Constants.maxSearchQueryLength {
            throw PresentError.invalidInput("Search query exceeds maximum length of \(Constants.maxSearchQueryLength) characters.")
        }

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
                WHERE a.isArchived = 0 AND a.isSystem = 0
                ORDER BY s.startedAt DESC
                LIMIT ?
                """
            return try Activity.fetchAll(db, sql: sql, arguments: [limit])
        }
    }

    public func getBreakActivity() async throws -> Activity {
        try await dbWriter.write { db in
            if let activity = try Activity
                .filter(Activity.Columns.isSystem == true)
                .filter(Activity.Columns.title == Constants.breakActivityTitle)
                .fetchOne(db) {
                return activity
            }
            // Self-heal: re-create Break if missing (e.g., DB corruption)
            let now = Date()
            var activity = Activity(
                title: Constants.breakActivityTitle,
                isSystem: true,
                createdAt: now,
                updatedAt: now
            )
            try activity.insert(db)
            activity.id = db.lastInsertedRowID
            return activity
        }
    }

    // MARK: - Notes

    public func appendNote(activityId: Int64, text: String) async throws -> Activity {
        let sanitizedText = try Validation.sanitize(text, fieldName: "Note text", maxLength: Constants.maxNotesLength)

        return try await dbWriter.write { db in
            guard var activity = try Activity.fetchOne(db, key: activityId) else {
                throw PresentError.activityNotFound(activityId)
            }

            let newNotes: String
            if let existing = activity.notes, !existing.isEmpty {
                newNotes = existing + "\n" + sanitizedText
            } else {
                newNotes = sanitizedText
            }

            // Check combined length
            if newNotes.count > Constants.maxNotesLength {
                throw PresentError.invalidInput("Notes would exceed maximum length of \(Constants.maxNotesLength) characters.")
            }

            activity.notes = newNotes
            activity.updatedAt = Date()
            try activity.update(db)
            return activity
        }
    }

    // MARK: - Tags

    public func createTag(name: String) async throws -> Tag {
        let trimmed = try Validation.sanitize(name, fieldName: "Tag name", maxLength: Constants.maxTagNameLength)

        return try await dbWriter.write { db in
            // Case-insensitive uniqueness check
            let existing = try Tag
                .filter(Tag.Columns.name.collating(.nocase) == trimmed)
                .fetchOne(db)
            if let existing {
                throw PresentError.invalidInput("A tag named \"\(existing.name)\" already exists.")
            }

            var tag = Tag(name: trimmed)
            try tag.insert(db)
            tag.id = db.lastInsertedRowID
            return tag
        }
    }

    public func getTag(id: Int64) async throws -> Tag {
        try await dbWriter.read { db in
            guard let tag = try Tag.fetchOne(db, key: id) else {
                throw PresentError.tagNotFound(id)
            }
            return tag
        }
    }

    public func updateTag(id: Int64, name: String) async throws -> Tag {
        let trimmed = try Validation.sanitize(name, fieldName: "Tag name", maxLength: Constants.maxTagNameLength)

        return try await dbWriter.write { db in
            guard var tag = try Tag.fetchOne(db, key: id) else {
                throw PresentError.tagNotFound(id)
            }

            // Case-insensitive uniqueness check (exclude self)
            let existing = try Tag
                .filter(Tag.Columns.name.collating(.nocase) == trimmed)
                .filter(Tag.Columns.id != id)
                .fetchOne(db)
            if let existing {
                throw PresentError.invalidInput("A tag named \"\(existing.name)\" already exists.")
            }

            tag.name = trimmed
            tag.updatedAt = Date()
            try tag.update(db)
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
        _ = try await dbWriter.write { db in
            try ActivityTag
                .filter(ActivityTag.Columns.activityId == activityId && ActivityTag.Columns.tagId == tagId)
                .deleteAll(db)
        }
    }

    public func setActivityTags(activityId: Int64, tagIds: [Int64]) async throws -> [Tag] {
        try await dbWriter.write { db in
            guard try Activity.fetchOne(db, key: activityId) != nil else {
                throw PresentError.activityNotFound(activityId)
            }

            // Validate all tags exist
            for tagId in tagIds {
                guard try Tag.fetchOne(db, key: tagId) != nil else {
                    throw PresentError.tagNotFound(tagId)
                }
            }

            // Delete existing tags
            try ActivityTag.filter(ActivityTag.Columns.activityId == activityId).deleteAll(db)

            // Insert new tags
            var tags: [Tag] = []
            for tagId in tagIds {
                try ActivityTag(activityId: activityId, tagId: tagId).insert(db)
                if let tag = try Tag.fetchOne(db, key: tagId) {
                    tags.append(tag)
                }
            }

            return tags.sorted { $0.name < $1.name }
        }
    }

    public func tagsForActivity(activityId: Int64) async throws -> [Tag] {
        try await dbWriter.read { db in
            let sql = """
                SELECT t.*
                FROM tag t
                INNER JOIN activity_tag at ON at.tagId = t.id
                WHERE at.activityId = ?
                ORDER BY t.name
                """
            return try Tag.fetchAll(db, sql: sql, arguments: [activityId])
        }
    }

    public func tagsForActivities(activityIds: [Int64]) async throws -> [Int64: [Tag]] {
        guard !activityIds.isEmpty else { return [:] }
        return try await dbWriter.read { db in
            let placeholders = activityIds.map { _ in "?" }.joined(separator: ", ")
            let sql = """
                SELECT at.activityId, t.*
                FROM tag t
                INNER JOIN activity_tag at ON at.tagId = t.id
                WHERE at.activityId IN (\(placeholders))
                ORDER BY t.name
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(activityIds))
            var result: [Int64: [Tag]] = [:]
            for row in rows {
                let activityId: Int64 = row["activityId"]
                let tag = try Tag(row: row)
                result[activityId, default: []].append(tag)
            }
            return result
        }
    }

    // MARK: - Segments

    public func segmentsForSessions(sessionIds: [Int64]) async throws -> [Int64: [SessionSegment]] {
        guard !sessionIds.isEmpty else { return [:] }
        return try await dbWriter.read { db in
            let segments = try SessionSegment
                .filter(sessionIds.contains(SessionSegment.Columns.sessionId))
                .order(SessionSegment.Columns.startedAt)
                .fetchAll(db)
            return Dictionary(grouping: segments, by: \.sessionId)
        }
    }

    public func sessionDayPortions(sessionIds: [Int64], date: Date) async throws -> [Int64: Int] {
        guard !sessionIds.isEmpty else { return [:] }
        return try await dbWriter.read { db in
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [:] }

            let placeholders = sessionIds.map { _ in "?" }.joined(separator: ", ")
            let sql = """
                SELECT ss.sessionId,
                    COALESCE(SUM(
                        MAX(0,
                            CAST(strftime('%s', MIN(COALESCE(ss.endedAt, ?), ?)) AS INTEGER) -
                            CAST(strftime('%s', MAX(ss.startedAt, ?)) AS INTEGER)
                        )
                    ), 0) as todaySecs
                FROM session_segment ss
                WHERE ss.sessionId IN (\(placeholders))
                  AND ss.startedAt < ? AND (ss.endedAt > ? OR ss.endedAt IS NULL)
                GROUP BY ss.sessionId
                """

            let now = Date()
            var values: [any DatabaseValueConvertible] = [now, endOfDay, startOfDay]
            values.append(contentsOf: sessionIds)
            values.append(contentsOf: [endOfDay, startOfDay] as [Date])

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values))
            var result: [Int64: Int] = [:]
            for row in rows {
                let sessionId: Int64 = row["sessionId"]
                let secs: Int = row["todaySecs"]
                result[sessionId] = secs
            }
            return result
        }
    }

    // MARK: - Reports

    public func activitySummary(from startDate: Date, to endDate: Date, includeArchived: Bool) async throws -> [ActivitySummary] {
        try await dbWriter.read { db in
            let archiveFilter = includeArchived ? "" : " AND a.isArchived = 0"
            let sql = """
                SELECT a.*,
                    COALESCE(SUM(
                        MAX(0,
                            CAST(strftime('%s', MIN(ss.endedAt, ?)) AS INTEGER) -
                            CAST(strftime('%s', MAX(ss.startedAt, ?)) AS INTEGER)
                        )
                    ), 0) as totalSecs,
                    COUNT(DISTINCT s.id) as sessCount
                FROM activity a
                INNER JOIN session s ON s.activityId = a.id
                INNER JOIN session_segment ss ON ss.sessionId = s.id
                WHERE s.state = ?
                  AND s.startedAt < ? AND (s.endedAt > ? OR s.endedAt IS NULL)
                  AND ss.endedAt IS NOT NULL
                  AND ss.startedAt < ? AND ss.endedAt > ?
                  \(archiveFilter)
                GROUP BY a.id
                ORDER BY totalSecs DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [
                endDate, startDate,
                SessionState.completed.rawValue,
                endDate, startDate,
                endDate, startDate
            ])

            return rows.map { row in
                let activity = try! Activity(row: row)
                let secs: Int = row["totalSecs"]
                let count: Int = row["sessCount"]
                return ActivitySummary(activity: activity, totalSeconds: secs, sessionCount: count)
            }
        }
    }

    public func dailySummary(date: Date, includeArchived: Bool, roundToMinute: Bool) async throws -> DailySummary {
        try await dbWriter.read { db in
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

            let archiveFilter = includeArchived ? "" : " AND a.isArchived = 0"

            let sql: String
            if roundToMinute {
                // Floor each session's day-overlap to the minute before summing per activity.
                // Ensures the activity total matches the sum of individually displayed durations.
                sql = """
                    SELECT a.*,
                        COALESCE(SUM(floored.sessionSecs), 0) as totalSecs,
                        COUNT(floored.sessionId) as sessCount
                    FROM activity a
                    INNER JOIN (
                        SELECT s.activityId, s.id as sessionId,
                            (COALESCE(SUM(
                                MAX(0,
                                    CAST(strftime('%s', MIN(ss.endedAt, ?)) AS INTEGER) -
                                    CAST(strftime('%s', MAX(ss.startedAt, ?)) AS INTEGER)
                                )
                            ), 0) / 60) * 60 as sessionSecs
                        FROM session s
                        INNER JOIN session_segment ss ON ss.sessionId = s.id
                        WHERE s.state = ?
                          AND s.startedAt < ? AND (s.endedAt > ? OR s.endedAt IS NULL)
                          AND ss.endedAt IS NOT NULL
                          AND ss.startedAt < ? AND ss.endedAt > ?
                        GROUP BY s.id
                    ) floored ON floored.activityId = a.id
                    WHERE 1=1 \(archiveFilter)
                    GROUP BY a.id
                    ORDER BY totalSecs DESC
                    """
            } else {
                // Raw seconds — used by CLI and data export.
                sql = """
                    SELECT a.*,
                        COALESCE(SUM(
                            MAX(0,
                                CAST(strftime('%s', MIN(ss.endedAt, ?)) AS INTEGER) -
                                CAST(strftime('%s', MAX(ss.startedAt, ?)) AS INTEGER)
                            )
                        ), 0) as totalSecs,
                        COUNT(DISTINCT s.id) as sessCount
                    FROM activity a
                    INNER JOIN session s ON s.activityId = a.id
                    INNER JOIN session_segment ss ON ss.sessionId = s.id
                    WHERE s.state = ?
                      AND s.startedAt < ? AND (s.endedAt > ? OR s.endedAt IS NULL)
                      AND ss.endedAt IS NOT NULL
                      AND ss.startedAt < ? AND ss.endedAt > ?
                      \(archiveFilter)
                    GROUP BY a.id
                    ORDER BY totalSecs DESC
                    """
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: [
                endOfDay, startOfDay,
                SessionState.completed.rawValue,
                endOfDay, startOfDay,
                endOfDay, startOfDay
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

            // Hourly breakdown — computed in Swift by splitting segments at hour boundaries
            let segmentSql = """
                SELECT ss.startedAt AS seg_startedAt, ss.endedAt AS seg_endedAt, a.*
                FROM session_segment ss
                INNER JOIN session s ON s.id = ss.sessionId
                INNER JOIN activity a ON a.id = s.activityId
                WHERE s.state = ?
                  AND s.startedAt < ? AND (s.endedAt > ? OR s.endedAt IS NULL)
                  AND ss.endedAt IS NOT NULL
                  AND ss.startedAt < ? AND ss.endedAt > ?
                  \(archiveFilter)
                ORDER BY ss.startedAt
                """

            let segmentRows = try Row.fetchAll(db, sql: segmentSql, arguments: [
                SessionState.completed.rawValue,
                endOfDay, startOfDay,
                endOfDay, startOfDay
            ])

            var hourActivitySeconds: [Int: [Int64: Int]] = [:]
            var activityById: [Int64: Activity] = [:]

            for row in segmentRows {
                let rawSegStart: Date = row["seg_startedAt"]
                let rawSegEnd: Date = row["seg_endedAt"]
                let activity = try Activity(row: row)
                guard let activityId = activity.id else { continue }
                activityById[activityId] = activity

                // Clamp segment boundaries to the queried day
                let segStart = max(rawSegStart, startOfDay)
                let segEnd = min(rawSegEnd, endOfDay)

                // Walk through the segment hour by hour, splitting at boundaries
                var cursor = segStart
                while cursor < segEnd {
                    let hourComponents = calendar.dateComponents([.year, .month, .day, .hour], from: cursor)
                    let hourStart = calendar.date(from: hourComponents)!
                    let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart)!
                    let sliceEnd = min(segEnd, nextHour)
                    let sliceSeconds = Int(sliceEnd.timeIntervalSince(cursor))
                    let hour = calendar.component(.hour, from: cursor)

                    hourActivitySeconds[hour, default: [:]][activityId, default: 0] += sliceSeconds
                    cursor = sliceEnd
                }
            }

            var hourlyBreakdown: [HourlyBucket] = []
            for hour in hourActivitySeconds.keys.sorted() {
                let actSecs = hourActivitySeconds[hour]!
                for (actId, secs) in actSecs.sorted(by: { $0.value > $1.value }) {
                    if let activity = activityById[actId] {
                        let finalSecs = roundToMinute ? TimeFormatting.floorToMinute(secs) : secs
                        hourlyBreakdown.append(HourlyBucket(hour: hour, activity: activity, totalSeconds: finalSecs))
                    }
                }
            }

            return DailySummary(date: startOfDay, totalSeconds: totalSeconds, sessionCount: totalSessions, activities: activities, hourlyBreakdown: hourlyBreakdown)
        }
    }

    public func weeklySummary(weekOf: Date, includeArchived: Bool, weekStartDay: Int = 1, roundToMinute: Bool = false) async throws -> WeeklySummary {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartDay
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: weekOf) else {
            return WeeklySummary(weekOf: weekOf, totalSeconds: 0, sessionCount: 0, dailyBreakdown: [], activities: [])
        }
        let startOfWeek = weekInterval.start
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) ?? weekInterval.end

        var dailyBreakdown: [DailySummary] = []
        var current = startOfWeek
        while current < endOfWeek {
            let daily = try await dailySummary(date: current, includeArchived: includeArchived, roundToMinute: roundToMinute)
            dailyBreakdown.append(daily)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
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

        let activities = activityMap.values.sorted {
            if $0.totalSeconds != $1.totalSeconds { return $0.totalSeconds > $1.totalSeconds }
            return $0.activity.title < $1.activity.title
        }
        return WeeklySummary(weekOf: startOfWeek, totalSeconds: totalSeconds, sessionCount: totalSessions, dailyBreakdown: dailyBreakdown, activities: activities)
    }

    public func monthlySummary(monthOf: Date, includeArchived: Bool, weekStartDay: Int = 1, roundToMinute: Bool = false) async throws -> MonthlySummary {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartDay
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthOf) else {
            return MonthlySummary(monthOf: monthOf, totalSeconds: 0, sessionCount: 0, weeklyBreakdown: [], dailyBreakdown: [], activities: [])
        }
        let startOfMonth = monthInterval.start
        let endOfMonth = monthInterval.end

        // Get weekly summaries for all weeks that overlap this month
        var weeklyBreakdown: [WeeklySummary] = []
        var current = startOfMonth
        var seenWeeks: Set<Date> = []

        while current < endOfMonth {
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: current) else { break }
            let weekStart = weekInterval.start
            if !seenWeeks.contains(weekStart) {
                seenWeeks.insert(weekStart)
                let weekly = try await weeklySummary(weekOf: current, includeArchived: includeArchived, weekStartDay: weekStartDay, roundToMinute: roundToMinute)
                weeklyBreakdown.append(weekly)
            }
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: current) else { break }
            current = nextWeek
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

        // Flatten daily breakdowns from weekly summaries, filtered to this calendar month
        var seenDates: Set<Date> = []
        var dailyBreakdown: [DailySummary] = []
        for weekly in weeklyBreakdown {
            for daily in weekly.dailyBreakdown {
                if daily.date >= startOfMonth && daily.date < endOfMonth && !seenDates.contains(daily.date) {
                    seenDates.insert(daily.date)
                    dailyBreakdown.append(daily)
                }
            }
        }
        dailyBreakdown.sort { $0.date < $1.date }

        let activities = activityMap.values.sorted {
            if $0.totalSeconds != $1.totalSeconds { return $0.totalSeconds > $1.totalSeconds }
            return $0.activity.title < $1.activity.title
        }
        return MonthlySummary(monthOf: startOfMonth, totalSeconds: totalSeconds, sessionCount: totalSessions, weeklyBreakdown: weeklyBreakdown, dailyBreakdown: dailyBreakdown, activities: activities)
    }

    public func tagSummary(from startDate: Date, to endDate: Date, includeArchived: Bool) async throws -> [TagSummary] {
        try await dbWriter.read { db in
            let archiveFilter = includeArchived ? "" : " AND a.isArchived = 0"
            let sql = """
                SELECT COALESCE(t.name, 'Untagged') as tagName,
                       COALESCE(SUM(
                           MAX(0,
                               CAST(strftime('%s', MIN(ss.endedAt, ?)) AS INTEGER) -
                               CAST(strftime('%s', MAX(ss.startedAt, ?)) AS INTEGER)
                           )
                       ), 0) as totalSecs,
                       COUNT(DISTINCT s.id) as sessCount
                FROM session s
                INNER JOIN activity a ON a.id = s.activityId
                INNER JOIN session_segment ss ON ss.sessionId = s.id
                LEFT JOIN activity_tag at2 ON at2.activityId = a.id
                LEFT JOIN tag t ON t.id = at2.tagId
                WHERE s.state = ?
                  AND s.startedAt < ? AND (s.endedAt > ? OR s.endedAt IS NULL)
                  AND ss.endedAt IS NOT NULL
                  AND ss.startedAt < ? AND ss.endedAt > ?
                  \(archiveFilter)
                GROUP BY tagName
                ORDER BY totalSecs DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [
                endDate, startDate,
                SessionState.completed.rawValue,
                endDate, startDate,
                endDate, startDate
            ])

            return rows.map { row in
                TagSummary(
                    tagName: row["tagName"],
                    totalSeconds: row["totalSecs"],
                    sessionCount: row["sessCount"]
                )
            }
        }
    }

    public func tagActivitySummary(from startDate: Date, to endDate: Date, includeArchived: Bool, roundToMinute: Bool = false) async throws -> [TagActivitySummary] {
        try await dbWriter.read { db in
            let archiveFilter = includeArchived ? "" : " AND a.isArchived = 0"

            let sql: String
            if roundToMinute {
                // Floor each session's date-range overlap to the minute before summing.
                sql = """
                    SELECT COALESCE(t.name, 'Untagged') as tagName,
                           a.id as activityId, a.title as activityTitle,
                           a.externalId, a.link, a.notes, a.isArchived, a.isSystem,
                           a.createdAt, a.updatedAt,
                           COALESCE(SUM(floored.sessionSecs), 0) as totalSecs,
                           COUNT(floored.sessionId) as sessCount
                    FROM activity a
                    INNER JOIN (
                        SELECT s.activityId, s.id as sessionId,
                            (COALESCE(SUM(
                                MAX(0,
                                    CAST(strftime('%s', MIN(ss.endedAt, ?)) AS INTEGER) -
                                    CAST(strftime('%s', MAX(ss.startedAt, ?)) AS INTEGER)
                                )
                            ), 0) / 60) * 60 as sessionSecs
                        FROM session s
                        INNER JOIN session_segment ss ON ss.sessionId = s.id
                        WHERE s.state = ?
                          AND s.startedAt < ? AND (s.endedAt > ? OR s.endedAt IS NULL)
                          AND ss.endedAt IS NOT NULL
                          AND ss.startedAt < ? AND ss.endedAt > ?
                        GROUP BY s.id
                    ) floored ON floored.activityId = a.id
                    LEFT JOIN activity_tag at2 ON at2.activityId = a.id
                    LEFT JOIN tag t ON t.id = at2.tagId
                    WHERE 1=1 \(archiveFilter)
                    GROUP BY tagName, a.id
                    ORDER BY tagName, totalSecs DESC
                    """
            } else {
                // Raw seconds — calculate segment overlap clamped to date range.
                sql = """
                    SELECT COALESCE(t.name, 'Untagged') as tagName,
                           a.id as activityId, a.title as activityTitle,
                           a.externalId, a.link, a.notes, a.isArchived, a.isSystem,
                           a.createdAt, a.updatedAt,
                           COALESCE(SUM(
                               MAX(0,
                                   CAST(strftime('%s', MIN(ss.endedAt, ?)) AS INTEGER) -
                                   CAST(strftime('%s', MAX(ss.startedAt, ?)) AS INTEGER)
                               )
                           ), 0) as totalSecs,
                           COUNT(DISTINCT s.id) as sessCount
                    FROM session s
                    INNER JOIN activity a ON a.id = s.activityId
                    INNER JOIN session_segment ss ON ss.sessionId = s.id
                    LEFT JOIN activity_tag at2 ON at2.activityId = a.id
                    LEFT JOIN tag t ON t.id = at2.tagId
                    WHERE s.state = ?
                      AND s.startedAt < ? AND (s.endedAt > ? OR s.endedAt IS NULL)
                      AND ss.endedAt IS NOT NULL
                      AND ss.startedAt < ? AND ss.endedAt > ?
                      \(archiveFilter)
                    GROUP BY tagName, a.id
                    ORDER BY tagName, totalSecs DESC
                    """
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: [
                endDate, startDate,
                SessionState.completed.rawValue,
                endDate, startDate,
                endDate, startDate
            ])

            // Group rows by tagName
            var tagGroups: [String: [ActivitySummary]] = [:]
            var tagOrder: [String] = []

            for row in rows {
                let tagName: String = row["tagName"]
                let activity = Activity(
                    id: row["activityId"],
                    title: row["activityTitle"],
                    externalId: row["externalId"],
                    link: row["link"],
                    notes: row["notes"],
                    isArchived: row["isArchived"],
                    isSystem: row["isSystem"],
                    createdAt: row["createdAt"],
                    updatedAt: row["updatedAt"]
                )
                let summary = ActivitySummary(
                    activity: activity,
                    totalSeconds: row["totalSecs"],
                    sessionCount: row["sessCount"]
                )
                if tagGroups[tagName] == nil {
                    tagOrder.append(tagName)
                }
                tagGroups[tagName, default: []].append(summary)
            }

            return tagOrder.map { tagName in
                let activities = tagGroups[tagName] ?? []
                let totalSecs = activities.reduce(0) { $0 + $1.totalSeconds }
                return TagActivitySummary(
                    tagName: tagName,
                    activities: activities,
                    totalSeconds: totalSecs,
                    activityCount: activities.count
                )
            }
            .sorted { $0.totalSeconds > $1.totalSeconds }
        }
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
        try Validation.validatePreferenceKey(key)

        try await dbWriter.write { db in
            let pref = Preference(key: key, value: value)
            try pref.save(db)
        }
    }

    public func listPreferences() async throws -> [(key: String, value: String)] {
        let stored = try await dbWriter.read { db in
            try Preference.fetchAll(db)
        }
        // Merge defaults with stored values (stored wins)
        var result: [(key: String, value: String)] = []
        let storedDict = Dictionary(uniqueKeysWithValues: stored.map { ($0.key, $0.value) })
        for (key, defaultValue) in PreferenceKey.defaults {
            let value = storedDict[key] ?? defaultValue
            result.append((key: key, value: value))
        }
        // Include any custom keys not in defaults
        for pref in stored where !PreferenceKey.defaults.contains(where: { $0.0 == pref.key }) {
            result.append((key: pref.key, value: pref.value))
        }
        return result
    }

    // MARK: - Bulk Operations

    public func countSessions(in range: BulkDeleteRange) async throws -> Int {
        let (start, end) = dateRange(for: range)
        return try await dbWriter.read { db in
            try Session
                .filter(Session.Columns.startedAt >= start && Session.Columns.startedAt < end)
                .fetchCount(db)
        }
    }

    public func deleteSessions(in range: BulkDeleteRange) async throws -> BulkDeleteResult {
        let (start, end) = dateRange(for: range)
        return try await dbWriter.write { db in
            var cancelledActive = false

            // Cancel active session if it falls within range
            if let active = try Session
                .filter(Session.Columns.state == SessionState.running.rawValue || Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db),
               active.startedAt >= start && active.startedAt < end {
                try active.delete(db)
                cancelledActive = true
            }

            // Delete all sessions in range
            let deleted = try Session
                .filter(Session.Columns.startedAt >= start && Session.Columns.startedAt < end)
                .deleteAll(db)

            return BulkDeleteResult(
                sessionsDeleted: deleted + (cancelledActive ? 1 : 0),
                activeSessionCancelled: cancelledActive
            )
        }
    }

    public func deleteAllActivities() async throws -> BulkDeleteResult {
        try await dbWriter.write { db in
            var cancelledActive = false

            // Cancel active session first (only for non-system activities)
            if let active = try Session
                .filter(Session.Columns.state == SessionState.running.rawValue || Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db) {
                let activity = try Activity.fetchOne(db, key: active.activityId)
                if activity?.isSystem != true {
                    try active.delete(db)
                    cancelledActive = true
                }
            }

            // Delete sessions for non-system activities
            let sessionsDeleted = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM session WHERE activityId IN (
                    SELECT id FROM activity WHERE isSystem = 0
                )
                """) ?? 0
            try db.execute(sql: """
                DELETE FROM session WHERE activityId IN (
                    SELECT id FROM activity WHERE isSystem = 0
                )
                """)

            // Delete non-system activities (cascade handles activity_tag)
            let activitiesDeleted = try Activity
                .filter(Activity.Columns.isSystem == false)
                .deleteAll(db)

            return BulkDeleteResult(
                sessionsDeleted: sessionsDeleted + (cancelledActive ? 1 : 0),
                activitiesDeleted: activitiesDeleted,
                activeSessionCancelled: cancelledActive
            )
        }
    }

    public func deleteAllTags() async throws -> BulkDeleteResult {
        try await dbWriter.write { db in
            let tagsDeleted = try Tag.deleteAll(db)
            // activity_tag rows cascade from tag deletion; activities untouched
            return BulkDeleteResult(tagsDeleted: tagsDeleted)
        }
    }

    public func factoryReset() async throws {
        try await dbWriter.write { db in
            // Cancel active session
            if let active = try Session
                .filter(Session.Columns.state == SessionState.running.rawValue || Session.Columns.state == SessionState.paused.rawValue)
                .fetchOne(db) {
                try active.delete(db)
            }

            // Delete everything
            try db.execute(sql: "DELETE FROM session")
            try db.execute(sql: "DELETE FROM activity_tag")
            try db.execute(sql: "DELETE FROM activity")
            try db.execute(sql: "DELETE FROM tag")
            try db.execute(sql: "DELETE FROM preference")

            // Re-seed default preferences
            for (key, value) in PreferenceKey.defaults {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO preference (key, value) VALUES (?, ?)",
                    arguments: [key, value]
                )
            }

            // Re-seed Break system activity
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO activity (title, isArchived, isSystem, createdAt, updatedAt)
                    VALUES (?, 0, 1, ?, ?)
                    """,
                arguments: [Constants.breakActivityTitle, now, now]
            )
        }
    }

    private func dateRange(for range: BulkDeleteRange) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        switch range {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        case .thisWeek:
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)!
            return (interval.start, interval.end)
        case .thisMonth:
            let interval = calendar.dateInterval(of: .month, for: now)!
            return (interval.start, interval.end)
        case .allTime:
            return (Date.distantPast, Date.distantFuture)
        }
    }

    // MARK: - Status

    public func todaySummary() async throws -> TodaySummary {
        let daily = try await dailySummary(date: Date(), includeArchived: false, roundToMinute: true)
        let current = try await currentSession()
        return TodaySummary(
            totalSeconds: daily.totalSeconds,
            sessionCount: daily.sessionCount,
            activities: daily.activities,
            currentSession: current
        )
    }
}
