import Foundation
import GRDB

/// Wraps GRDB's `DatabaseRegionObservation` to emit change notifications
/// as an `AsyncStream`. Keeps GRDB observation details in PresentCore so
/// the app layer does not need to import GRDB directly.
public final class DatabaseChangeNotifier: Sendable {
    private let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// Returns a stream that emits `()` whenever a committed transaction
    /// modifies any of the named tables.
    ///
    /// The stream stays active until cancelled. With `DatabasePool` (WAL mode)
    /// this also detects writes from external processes (e.g. the CLI).
    public func changes(tracking tableNames: [String]) -> AsyncStream<Void> {
        let tables = tableNames.map { Table($0) }
        let observation = DatabaseRegionObservation(tracking: tables)
        let writer = self.writer

        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: writer,
                onError: { error in
                    // Log but don't terminate — observation failures are
                    // non-fatal; the IPC fallback still works.
                    print("DatabaseChangeNotifier error: \(error)")
                },
                onChange: { _ in
                    continuation.yield()
                }
            )

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}
