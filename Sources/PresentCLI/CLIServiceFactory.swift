import PresentCore

enum CLIServiceFactory {
    static func makeService() throws -> PresentService {
        let dbManager = try DatabaseManager(path: DatabaseManager.defaultDatabasePath)
        return PresentService(databasePool: dbManager.writer)
    }
}
