import Foundation
import PresentCore

// MARK: - Cached Formatters

private enum ModelJSONFormatters {
    /// ISO8601 with internet datetime (e.g., "2026-02-14T15:30:45Z")
    nonisolated(unsafe) static let internetDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Standard JSON representations for CLI output
//
// Each model type defines a canonical toJSONDict() that ensures
// consistent field names and structure across all CLI commands.
//
// Nesting rules:
// - A session contains an activity (nested object under "activity" key).
// - An activity at the top level uses "id"; nested inside another object uses "activityId".
// - A tag at the top level uses "id"; nested inside another object uses "tagId".

extension Activity {

    /// Standard JSON representation for a top-level Activity response.
    func toJSONDict(tags: [Tag] = []) -> [String: Any] {
        var dict = toNestedJSONDict()
        // Top-level uses "id" not "activityId"
        dict.removeValue(forKey: "activityId")
        dict["id"] = id ?? 0
        dict["tags"] = tags.map { $0.toJSONDict() }
        return dict
    }

    /// JSON representation when nested inside another object (e.g., a session).
    /// Uses "activityId" to clarify context.
    func toNestedJSONDict() -> [String: Any] {
        let isoFormatter = ModelJSONFormatters.internetDateTime

        var dict: [String: Any] = [
            "activityId": id ?? 0,
            "title": title,
            "externalId": externalId as Any,
            "link": link as Any,
            "isArchived": isArchived,
            "isSystem": isSystem,
            "createdAt": isoFormatter.string(from: createdAt),
            "updatedAt": isoFormatter.string(from: updatedAt),
        ]
        if let notes { dict["notes"] = notes }
        return dict
    }

    /// Standard text field mapping for --field support.
    func toTextFields(tags: [Tag] = []) -> [String: String] {
        var fields: [String: String] = [
            "id": "\(id ?? 0)",
            "title": title,
            "isArchived": "\(isArchived)",
            "isSystem": "\(isSystem)",
            "createdAt": TimeFormatting.formatDate(createdAt),
            "updatedAt": TimeFormatting.formatDate(updatedAt),
        ]
        if let externalId { fields["externalId"] = externalId }
        if let link { fields["link"] = link }
        if let notes { fields["notes"] = notes }
        if !tags.isEmpty {
            fields["tags"] = tags.map { $0.name }.joined(separator: ", ")
        }
        return fields
    }
}

extension Session {

    /// Standard JSON representation for a Session.
    /// The activity is nested as an object under the "activity" key.
    func toJSONDict(activity: Activity? = nil) -> [String: Any] {
        let isoFormatter = ModelJSONFormatters.internetDateTime

        var dict: [String: Any] = [
            "sessionId": id ?? 0,
            "type": sessionType.rawValue,
            "state": state.rawValue,
            "startedAt": isoFormatter.string(from: startedAt),
        ]
        if let activity {
            dict["activity"] = activity.toNestedJSONDict()
        }
        if let endedAt {
            dict["endedAt"] = isoFormatter.string(from: endedAt)
        }
        if let durationSeconds {
            dict["durationSeconds"] = durationSeconds
        }
        if let timerLengthMinutes {
            dict["timerMinutes"] = timerLengthMinutes
        }
        if let breakMinutes {
            dict["breakMinutes"] = breakMinutes
        }
        if let note {
            dict["note"] = note
        }
        if let link {
            dict["link"] = link
        }
        if let ticketId {
            dict["ticketId"] = ticketId
        }
        if countdownBaseSeconds > 0 {
            dict["countdownBaseSeconds"] = countdownBaseSeconds
        }
        return dict
    }

    /// Standard text field mapping for --field support.
    /// Text fields remain flat for easy extraction.
    func toTextFields(activity: Activity? = nil) -> [String: String] {
        var fields: [String: String] = [
            "sessionId": "\(id ?? 0)",
            "activityId": "\(activityId)",
            "type": SessionTypeConfig.config(for: sessionType).displayName,
            "state": state.rawValue,
        ]
        if let activity {
            fields["activity"] = activity.title
        }
        if let durationSeconds {
            fields["durationSeconds"] = "\(durationSeconds)"
            fields["duration"] = TimeFormatting.formatDuration(seconds: durationSeconds)
        }
        if let timerLengthMinutes {
            fields["timerMinutes"] = "\(timerLengthMinutes)"
        }
        if let breakMinutes {
            fields["breakMinutes"] = "\(breakMinutes)"
        }
        if let note {
            fields["note"] = note
        }
        if let link {
            fields["link"] = link
        }
        if let ticketId {
            fields["ticketId"] = ticketId
        }
        if countdownBaseSeconds > 0 {
            fields["countdownBaseSeconds"] = "\(countdownBaseSeconds)"
        }
        return fields
    }
}

extension Tag {

    /// Standard JSON representation for a top-level Tag response.
    func toJSONDict() -> [String: Any] {
        let isoFormatter = ModelJSONFormatters.internetDateTime
        return [
            "id": id ?? 0,
            "name": name,
            "createdAt": isoFormatter.string(from: createdAt),
            "updatedAt": isoFormatter.string(from: updatedAt),
        ]
    }

    /// JSON representation when nested inside another object.
    func toNestedJSONDict() -> [String: Any] {
        let isoFormatter = ModelJSONFormatters.internetDateTime
        return [
            "tagId": id ?? 0,
            "name": name,
            "createdAt": isoFormatter.string(from: createdAt),
            "updatedAt": isoFormatter.string(from: updatedAt),
        ]
    }

    /// Standard text field mapping for --field support.
    func toTextFields() -> [String: String] {
        [
            "id": "\(id ?? 0)",
            "name": name,
            "createdAt": TimeFormatting.formatDate(createdAt),
            "updatedAt": TimeFormatting.formatDate(updatedAt),
        ]
    }
}

// MARK: - Report Summary Types

extension ActivitySummary {

    func toJSONDict() -> [String: Any] {
        [
            "activity": activity.toNestedJSONDict(),
            "totalSeconds": totalSeconds,
            "sessionCount": sessionCount,
        ]
    }
}

extension DailySummary {

    func toJSONDict() -> [String: Any] {
        [
            "date": ModelJSONFormatters.internetDateTime.string(from: date),
            "totalSeconds": totalSeconds,
            "sessionCount": sessionCount,
            "activities": activities.map { $0.toJSONDict() },
        ]
    }
}

extension WeeklySummary {

    func toJSONDict() -> [String: Any] {
        [
            "weekOf": ModelJSONFormatters.internetDateTime.string(from: weekOf),
            "totalSeconds": totalSeconds,
            "sessionCount": sessionCount,
            "dailyBreakdown": dailyBreakdown.map { $0.toJSONDict() },
            "activities": activities.map { $0.toJSONDict() },
        ]
    }
}

extension MonthlySummary {

    func toJSONDict() -> [String: Any] {
        [
            "monthOf": ModelJSONFormatters.internetDateTime.string(from: monthOf),
            "totalSeconds": totalSeconds,
            "sessionCount": sessionCount,
            "weeklyBreakdown": weeklyBreakdown.map { $0.toJSONDict() },
            "activities": activities.map { $0.toJSONDict() },
        ]
    }
}

extension TagSummary {

    func toJSONDict() -> [String: Any] {
        [
            "tagName": tagName,
            "totalSeconds": totalSeconds,
            "sessionCount": sessionCount,
        ]
    }
}

extension ExternalIdSummary {

    func toJSONDict() -> [String: Any] {
        var dict: [String: Any] = [
            "externalId": externalId,
            "totalSeconds": totalSeconds,
            "sessionCount": sessionCount,
            "activityNames": activityNames,
        ]
        if let sourceURL { dict["sourceURL"] = sourceURL }
        return dict
    }
}
