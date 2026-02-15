import Foundation

public enum SessionType: String, Codable, Sendable, CaseIterable {
    case work
    case rhythm
    case timebound
    case timebox
}

public enum SessionState: String, Codable, Sendable {
    case running
    case paused
    case completed
    case cancelled
}
