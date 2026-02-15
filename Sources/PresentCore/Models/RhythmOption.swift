import Foundation

public struct RhythmOption: Codable, Sendable, Equatable, Hashable {
    public let focusMinutes: Int
    public let breakMinutes: Int

    public init(focusMinutes: Int, breakMinutes: Int) {
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
    }
}
