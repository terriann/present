import ArgumentParser
import PresentCore

extension SessionType {
    /// Parse a raw string into a SessionType or exit with a descriptive error.
    static func parseOrFail(_ raw: String) throws -> SessionType {
        guard let type = SessionType(rawValue: raw) else {
            print("Invalid session type: \(raw). Use: work, rhythm, timebound.")
            throw ExitCode.failure
        }
        return type
    }
}
