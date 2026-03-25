import Foundation

/// Write error messages to stderr so they don't mix with structured output on stdout.
enum CLIError {
    static func print(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
