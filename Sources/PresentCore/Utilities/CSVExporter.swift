import Foundation
import GRDB

public enum CSVExporter {
    public static func export(rows: [Row]) -> Data {
        var csv = "Session ID,Activity,Session Type,Started At,Ended At,Duration (seconds),Status\n"

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for row in rows {
            let id: Int64 = row["id"]
            let title: String = row["title"]
            let sessionType: String = row["sessionType"]
            let startedAt: Date = row["startedAt"]
            let endedAt: Date? = row["endedAt"]
            let durationSeconds: Int? = row["durationSeconds"]
            let state: String = row["state"]

            let escapedTitle = title.contains(",") ? "\"\(title)\"" : title
            let endedStr = endedAt.map { formatter.string(from: $0) } ?? ""
            let durationStr = durationSeconds.map { String($0) } ?? ""

            csv += "\(id),\(escapedTitle),\(sessionType),\(formatter.string(from: startedAt)),\(endedStr),\(durationStr),\(state)\n"
        }

        return csv.data(using: .utf8) ?? Data()
    }
}
