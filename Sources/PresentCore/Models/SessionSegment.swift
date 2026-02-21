import Foundation
import GRDB

public struct SessionSegment: Codable, Sendable, Identifiable, Equatable {
    public var id: Int64?
    public var sessionId: Int64
    public var startedAt: Date
    public var endedAt: Date?   // nil while segment is open (active)

    public init(
        id: Int64? = nil,
        sessionId: Int64,
        startedAt: Date,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

extension SessionSegment: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "session_segment"

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let sessionId = Column(CodingKeys.sessionId)
        static let startedAt = Column(CodingKeys.startedAt)
        static let endedAt = Column(CodingKeys.endedAt)
    }

    public static let session = belongsTo(Session.self)
}
