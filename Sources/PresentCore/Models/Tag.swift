import Foundation
import GRDB

public struct Tag: Codable, Sendable, Identifiable, Equatable {
    public var id: Int64?
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: Int64? = nil, name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Tag: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "tag"

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    public static let activityTags = hasMany(ActivityTag.self)
    public static let activities = hasMany(Activity.self, through: activityTags, using: ActivityTag.activity)
}
