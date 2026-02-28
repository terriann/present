enum ReportPeriod: String, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var timeLabel: String {
        switch self {
        case .daily: "Hour"
        case .weekly: "Day"
        case .monthly: "Day"
        }
    }
}
