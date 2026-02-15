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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
                t.column("plannedStart", .datetime)
                t.column("plannedEnd", .datetime)
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

        try migrator.migrate(writer)
    }
}
