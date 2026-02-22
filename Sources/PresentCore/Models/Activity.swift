import Foundation
import GRDB

public struct Activity: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: Int64?
    public var title: String
    public var externalId: String?
    public var link: String?
    public var notes: String?
    public var isArchived: Bool
    public var isSystem: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        title: String,
        externalId: String? = nil,
        link: String? = nil,
        notes: String? = nil,
        isArchived: Bool = false,
        isSystem: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.externalId = externalId
        self.link = link
        self.notes = notes
        self.isArchived = isArchived
        self.isSystem = isSystem
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Activity: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "activity"

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let externalId = Column(CodingKeys.externalId)
        static let link = Column(CodingKeys.link)
        static let notes = Column(CodingKeys.notes)
        static let isArchived = Column(CodingKeys.isArchived)
        static let isSystem = Column(CodingKeys.isSystem)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    public static let sessions = hasMany(Session.self)
    public static let activityTags = hasMany(ActivityTag.self)
    public static let tags = hasMany(Tag.self, through: activityTags, using: ActivityTag.tag)
}
