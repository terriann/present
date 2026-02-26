import Testing
import Foundation
@testable import PresentCore

@Suite("DatabaseManager Tests")
struct DatabaseManagerTests {

    @Test func inMemoryInit() throws {
        let dbManager = try DatabaseManager(inMemory: true)
        try dbManager.writer.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master")
            #expect((count ?? 0) > 0) // database is initialized with tables
        }
    }

    @Test func defaultPreferences() throws {
        let dbManager = try DatabaseManager(inMemory: true)
        try dbManager.writer.read { db in
            let pref = try Preference.fetchOne(db, key: PreferenceKey.defaultRhythmMinutes)
            #expect(pref?.value == "25")

            let longBreak = try Preference.fetchOne(db, key: PreferenceKey.longBreakMinutes)
            #expect(longBreak?.value == "15")
        }
    }

    @Test func tablesCreated() throws {
        let dbManager = try DatabaseManager(inMemory: true)
        try dbManager.writer.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            #expect(tables.contains("activity"))
            #expect(tables.contains("session"))
            #expect(tables.contains("tag"))
            #expect(tables.contains("activity_tag"))
            #expect(tables.contains("preference"))
        }
    }

    @Test func ftsTableCreated() throws {
        let dbManager = try DatabaseManager(inMemory: true)
        try dbManager.writer.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='activity_fts'")
            #expect(tables.contains("activity_fts"))
        }
    }
}
