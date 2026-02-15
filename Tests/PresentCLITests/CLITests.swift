import Testing
import Foundation
@testable import PresentCore

@Suite("CLI Tests")
struct CLITests {
    @Test func serviceCreation() throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let service = PresentService(databasePool: dbManager.writer)
        #expect(service != nil)
    }
}
