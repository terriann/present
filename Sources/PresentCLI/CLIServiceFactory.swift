import Foundation
import PresentCore

enum CLIServiceFactory {
    /// Override for testing. When set, `makeService()` returns this instead of
    /// creating a real database-backed service. Reset to `nil` after each test.
    private static let lock = NSLock()
    // Safe: access is serialized through `lock` in the computed property below.
    nonisolated(unsafe) private static var _serviceOverride: PresentService?
    static var serviceOverride: PresentService? {
        get { lock.lock(); defer { lock.unlock() }; return _serviceOverride }
        set { lock.lock(); defer { lock.unlock() }; _serviceOverride = newValue }
    }

    static func makeService() throws -> PresentService {
        if let override = serviceOverride { return override }
        let dbManager = try DatabaseManager(path: DatabaseManager.defaultDatabasePath())
        return PresentService(databasePool: dbManager.writer)
    }
}
