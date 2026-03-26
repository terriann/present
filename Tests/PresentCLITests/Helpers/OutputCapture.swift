import Foundation

/// Captures stdout output from a closure for test assertions.
/// Redirects stdout to a pipe, runs the closure, then restores stdout.
///
/// **Thread safety:** This hijacks the process-global `STDOUT_FILENO`. Callers must
/// run inside a `.serialized` suite to prevent other tests from writing to stdout
/// during the capture window. Non-serialized suites in the same process could
/// intermix output if they print concurrently.
func captureStdout(_ body: () async throws -> Void) async throws -> String {
    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    do {
        try await body()
    } catch {
        // Restore stdout before rethrowing so test failure output is visible
        fflush(stdout)
        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)
        pipe.fileHandleForWriting.closeFile()
        throw error
    }

    fflush(stdout)
    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
