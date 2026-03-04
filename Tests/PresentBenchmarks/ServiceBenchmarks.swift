import XCTest
@testable import PresentCore

/// Performance benchmarks for PresentService hot paths.
///
/// Each test measures clock time, CPU time, and peak memory using XCTest's
/// `measure(metrics:)` API against an in-memory database seeded with
/// realistic data volume (50 activities, 10 tags, 1000 sessions).
final class ServiceBenchmarks: XCTestCase {
    private var service: PresentService!
    private var seeder: BenchmarkSeeder!

    override func setUp() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        service = PresentService(databasePool: dbManager.writer)
        seeder = BenchmarkSeeder(service: service)
        try await seeder.seed()
    }

    override func tearDown() {
        service = nil
        seeder = nil
    }

    // MARK: - Metrics

    private var benchmarkMetrics: [XCTMetric] {
        [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]
    }

    private var benchmarkOptions: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        return options
    }

    // MARK: - Session Lifecycle

    func testStartStopSessionPerformance() {
        let activityId = seeder.activityIds[0]
        let svc = service!

        measure(metrics: benchmarkMetrics, options: benchmarkOptions) {
            let exp = expectation(description: "startStop")
            Task {
                _ = try await svc.startSession(activityId: activityId, type: .work)
                _ = try await svc.stopSession()
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    // MARK: - Database Queries

    func testListActivitiesPerformance() {
        let svc = service!

        measure(metrics: benchmarkMetrics, options: benchmarkOptions) {
            let exp = expectation(description: "listActivities")
            Task {
                _ = try await svc.listActivities(includeArchived: true, includeSystem: true)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    func testListSessionsPerformance() {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -30, to: endDate)!
        let svc = service!

        measure(metrics: benchmarkMetrics, options: benchmarkOptions) {
            let exp = expectation(description: "listSessions")
            Task {
                _ = try await svc.listSessions(
                    from: startDate, to: endDate,
                    includeArchived: true
                )
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    func testSearchActivitiesPerformance() {
        let svc = service!

        measure(metrics: benchmarkMetrics, options: benchmarkOptions) {
            let exp = expectation(description: "searchActivities")
            Task {
                _ = try await svc.searchActivities(query: "Benchmark")
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    // MARK: - Report Aggregation

    func testDailySummaryPerformance() {
        let svc = service!

        measure(metrics: benchmarkMetrics, options: benchmarkOptions) {
            let exp = expectation(description: "dailySummary")
            Task {
                _ = try await svc.dailySummary(
                    date: Date(), includeArchived: true, roundToMinute: true
                )
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    func testWeeklySummaryPerformance() {
        let svc = service!

        measure(metrics: benchmarkMetrics, options: benchmarkOptions) {
            let exp = expectation(description: "weeklySummary")
            Task {
                _ = try await svc.weeklySummary(
                    weekOf: Date(), includeArchived: true,
                    weekStartDay: 1, roundToMinute: true
                )
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    // MARK: - Data Refresh Cycle

    /// Simulates the queries DataRefreshCoordinator runs on app foreground:
    /// current session + daily summary + activity list.
    func testDataRefreshCyclePerformance() {
        let svc = service!

        measure(metrics: benchmarkMetrics, options: benchmarkOptions) {
            let exp = expectation(description: "dataRefresh")
            Task {
                _ = try await svc.currentSession()
                _ = try await svc.dailySummary(
                    date: Date(), includeArchived: false, roundToMinute: true
                )
                _ = try await svc.listActivities(
                    includeArchived: false, includeSystem: false
                )
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }
}
