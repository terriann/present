import Foundation

public struct SessionTypeConfig: Sendable {
    public let type: SessionType
    public let displayName: String
    public let description: String

    public static let all: [SessionTypeConfig] = [
        SessionTypeConfig(
            type: .work,
            displayName: "Work Session",
            description: "An open-ended session for tracking work without a fixed time limit. Start when you begin, stop when you're done."
        ),
        SessionTypeConfig(
            type: .rhythm,
            displayName: "Rhythm Session",
            description: "A structured focus cycle with timed work sessions followed by short breaks. After four sessions, take a longer break to recharge."
        ),
        SessionTypeConfig(
            type: .timebound,
            displayName: "Timebound",
            description: "Set a fixed amount of time to focus. A gentle alert lets you know when time is up."
        ),
        SessionTypeConfig(
            type: .timebox,
            displayName: "Time Box",
            description: "Plan a block of time for an activity with a specific start and end. You'll be reminded when it's time to begin."
        ),
    ]

    public static func config(for type: SessionType) -> SessionTypeConfig {
        all.first { $0.type == type }!
    }
}
