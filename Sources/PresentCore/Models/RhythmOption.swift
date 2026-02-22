import Foundation

public struct RhythmOption: Codable, Sendable, Equatable, Hashable {
    public let focusMinutes: Int
    public let breakMinutes: Int

    public init(focusMinutes: Int, breakMinutes: Int) {
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
    }

    /// Compact display label for rhythm durations (e.g. "25m / 5m").
    public var displayLabel: String {
        "\(focusMinutes)m / \(breakMinutes)m"
    }

    /// Verbose display label for settings and configuration (e.g. "25 minute focus / 5 minute break").
    public var settingsLabel: String {
        "\(focusMinutes) minute focus / \(breakMinutes) minute break"
    }
}
