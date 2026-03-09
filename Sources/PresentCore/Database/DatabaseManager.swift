import Foundation
import GRDB

public final class DatabaseManager: Sendable {
    public let writer: any DatabaseWriter

    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: path, configuration: config)
        self.writer = pool
        try Self.migrate(pool)
    }

    /// In-memory database for testing
    public init(inMemory: Bool = true) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        self.writer = queue
        try Self.migrate(queue)
    }

    public static var defaultDatabasePath: String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        let presentDir = appSupport.appendingPathComponent("Present", isDirectory: true)
        try? FileManager.default.createDirectory(at: presentDir, withIntermediateDirectories: true)
        return presentDir.appendingPathComponent("present.sqlite").path
    }

    private static func migrate(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1-create-tables") { db in
            try db.create(table: "activity") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("externalId", .text)
                t.column("link", .text)
                t.column("notes", .text)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "tag") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
            }

            try db.create(table: "activity_tag") { t in
                t.column("activityId", .integer).notNull()
                    .references("activity", onDelete: .cascade)
                t.column("tagId", .integer).notNull()
                    .references("tag", onDelete: .cascade)
                t.primaryKey(["activityId", "tagId"])
            }

            try db.create(table: "session") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("activityId", .integer).notNull()
                    .references("activity")
                t.column("sessionType", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("durationSeconds", .integer)
                t.column("timerLengthMinutes", .integer)
                t.column("rhythmSessionIndex", .integer)
                t.column("state", .text).notNull()
                t.column("totalPausedSeconds", .integer).notNull().defaults(to: 0)
                t.column("lastPausedAt", .datetime)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "preference") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }

            // Seed default preferences
            for (key, value) in PreferenceKey.defaults {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO preference (key, value) VALUES (?, ?)",
                    arguments: [key, value]
                )
            }

            // FTS5 virtual table for activity search
            try db.create(virtualTable: "activity_fts", using: FTS5()) { t in
                t.tokenizer = .porter()
                t.synchronize(withTable: "activity")
                t.column("title")
                t.column("notes")
            }
        }

        migrator.registerMigration("v2-add-session-break-minutes") { db in
            try db.alter(table: "session") { t in
                t.add(column: "breakMinutes", .integer)
            }

            // Update rhythmDurationOptions to new colon-pair format
            try db.execute(
                sql: "UPDATE preference SET value = ? WHERE key = ? AND value = ?",
                arguments: ["25:5,30:5,45:10", PreferenceKey.rhythmDurationOptions, "25,30,45"]
            )

            // Remove deprecated shortBreakMinutes preference
            try db.execute(
                sql: "DELETE FROM preference WHERE key = ?",
                arguments: ["shortBreakMinutes"]
            )
        }

        migrator.registerMigration("v3-remove-timebox-fields") { db in
            let columns = try db.columns(in: "session").map(\.name)
            if columns.contains("plannedStart") || columns.contains("plannedEnd") {
                try db.alter(table: "session") { t in
                    if columns.contains("plannedStart") { t.drop(column: "plannedStart") }
                    if columns.contains("plannedEnd") { t.drop(column: "plannedEnd") }
                }
            }
        }

        migrator.registerMigration("v4-seed-default-timebound-minutes") { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO preference (key, value) VALUES (?, ?)",
                arguments: [PreferenceKey.defaultTimeboundMinutes, "\(Constants.defaultTimeboundMinutes)"]
            )
        }

        migrator.registerMigration("v5-add-tag-timestamps") { db in
            try db.alter(table: "tag") { t in
                t.add(column: "createdAt", .datetime).defaults(sql: "'1970-01-01 00:00:00'")
                t.add(column: "updatedAt", .datetime).defaults(sql: "'1970-01-01 00:00:00'")
            }
            // Backfill existing tags with current timestamp
            try db.execute(sql: """
                UPDATE tag SET createdAt = CURRENT_TIMESTAMP, updatedAt = CURRENT_TIMESTAMP
                """)
        }

        migrator.registerMigration("v6-add-session-segment") { db in
            try db.create(table: "session_segment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .integer).notNull()
                    .references("session", onDelete: .cascade)
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
            }

            // Backfill completed sessions:
            // - No pauses: exact segment from startedAt to endedAt
            // - Has pauses: best approximation — active time anchored at startedAt
            try db.execute(sql: """
                INSERT INTO session_segment (sessionId, startedAt, endedAt)
                SELECT id,
                       startedAt,
                       CASE
                           WHEN totalPausedSeconds = 0 THEN endedAt
                           ELSE datetime(startedAt, '+' || durationSeconds || ' seconds')
                       END
                FROM session
                WHERE state = 'completed'
                  AND endedAt IS NOT NULL
                  AND durationSeconds IS NOT NULL
                """)
        }

        migrator.registerMigration("v7-add-system-activity") { db in
            try db.alter(table: "activity") { t in
                t.add(column: "isSystem", .boolean).notNull().defaults(to: false)
            }

            // Seed the "Break" system activity
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO activity (title, isArchived, isSystem, createdAt, updatedAt)
                    VALUES (?, 0, 1, ?, ?)
                    """,
                arguments: [Constants.breakActivityTitle, now, now]
            )
        }

        migrator.registerMigration("v8-add-session-notes-and-link") { db in
            try db.alter(table: "session") { t in
                t.add(column: "note", .text)
                t.add(column: "link", .text)
                t.add(column: "ticketId", .text)
            }

            try db.create(virtualTable: "session_fts", using: FTS5()) { t in
                t.tokenizer = .porter()
                t.synchronize(withTable: "session")
                t.column("note")
                t.column("ticketId")
            }
        }

        migrator.registerMigration("v9-add-countdown-base-seconds") { db in
            try db.alter(table: "session") { t in
                t.add(column: "countdownBaseSeconds", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v10-add-session-indexes") { db in
            // Clean up orphaned session_segments that reference deleted sessions.
            // GRDB validates foreign key constraints after each migration, so any
            // pre-existing orphans would cause the migration to fail.
            try db.execute(sql: """
                DELETE FROM session_segment
                WHERE sessionId NOT IN (SELECT id FROM session)
                """)
            let orphansDeleted = db.changesCount
            if orphansDeleted > 0 {
                print("[v10 migration] Purged \(orphansDeleted) orphaned session_segment row(s)")
            }

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_state ON session(state)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_startedAt ON session(startedAt)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_endedAt ON session(endedAt)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_activityId_state ON session(activityId, state)")

        }

        // v11: indexes for session_segment joins/ranges and recentActivities covering query
        migrator.registerMigration("v11-add-segment-and-covering-indexes") { db in
            // session_segment indexes for join and range queries (#256)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_segment_sessionId ON session_segment(sessionId)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_segment_startedAt_endedAt ON session_segment(startedAt, endedAt)")

            // Covering index for recentActivities GROUP BY + MAX query (#265)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_activityId_startedAt ON session(activityId, startedAt)")
        }

        try migrator.migrate(writer)
    }
}
