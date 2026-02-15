import Foundation
import GRDB

public struct Session: Codable, Sendable, Identifiable, Equatable {
    public var id: Int64?
    public var activityId: Int64
    public var sessionType: SessionType
    public var startedAt: Date
    public var endedAt: Date?
    public var durationSeconds: Int?
    public var timerLengthMinutes: Int?
    public var rhythmSessionIndex: Int?
    public var state: SessionState
    public var totalPausedSeconds: Int
    public var lastPausedAt: Date?
    public var breakMinutes: Int?
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        activityId: Int64,
        sessionType: SessionType,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        durationSeconds: Int? = nil,
        timerLengthMinutes: Int? = nil,
        rhythmSessionIndex: Int? = nil,
        state: SessionState = .running,
        totalPausedSeconds: Int = 0,
        lastPausedAt: Date? = nil,
        breakMinutes: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.activityId = activityId
        self.sessionType = sessionType
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.timerLengthMinutes = timerLengthMinutes
        self.rhythmSessionIndex = rhythmSessionIndex
        self.state = state
        self.totalPausedSeconds = totalPausedSeconds
        self.lastPausedAt = lastPausedAt
        self.breakMinutes = breakMinutes
        self.createdAt = createdAt
    }
}

extension Session: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "session"

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let activityId = Column(CodingKeys.activityId)
        static let sessionType = Column(CodingKeys.sessionType)
        static let startedAt = Column(CodingKeys.startedAt)
        static let endedAt = Column(CodingKeys.endedAt)
        static let durationSeconds = Column(CodingKeys.durationSeconds)
        static let timerLengthMinutes = Column(CodingKeys.timerLengthMinutes)
        static let rhythmSessionIndex = Column(CodingKeys.rhythmSessionIndex)
        static let state = Column(CodingKeys.state)
        static let totalPausedSeconds = Column(CodingKeys.totalPausedSeconds)
        static let lastPausedAt = Column(CodingKeys.lastPausedAt)
        static let breakMinutes = Column(CodingKeys.breakMinutes)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    public static let activity = belongsTo(Activity.self)
}
