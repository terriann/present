import Foundation
import GRDB

public struct ActivityTag: Codable, Sendable, Equatable {
    public var activityId: Int64
    public var tagId: Int64

    public init(activityId: Int64, tagId: Int64) {
        self.activityId = activityId
        self.tagId = tagId
    }
}

extension ActivityTag: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "activity_tag"

    public enum Columns {
        static let activityId = Column(CodingKeys.activityId)
        static let tagId = Column(CodingKeys.tagId)
    }

    public static let activity = belongsTo(Activity.self)
    public static let tag = belongsTo(Tag.self)
}
