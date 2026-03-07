import Foundation

public enum IPCMessage: Codable, Sendable {
    case sessionStarted
    case sessionPaused
    case sessionResumed
    case sessionStopped
    case sessionCancelled
    case sessionUpdated
    case sessionConverted
    case activityUpdated
    case dataChanged

    public var data: Data? {
        try? JSONEncoder().encode(self)
    }

    public static func from(data: Data) -> IPCMessage? {
        try? JSONDecoder().decode(IPCMessage.self, from: data)
    }
}
