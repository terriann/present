import Foundation
@testable import PresentCore

/// Seeds an in-memory database with realistic data for performance benchmarks.
///
/// Default volume: 50 activities, 10 tags, 1000 completed sessions spread
/// across 180 days. Distribution is deterministic (modular arithmetic, no
/// randomness) so results are reproducible across runs.
final class BenchmarkSeeder {
    let service: PresentService
    private(set) var activityIds: [Int64] = []
    private(set) var tagIds: [Int64] = []

    static let defaultActivityCount = 50
    static let defaultSessionCount = 1000
    static let defaultTagCount = 10
    static let daysSpan = 180

    init(service: PresentService) {
        self.service = service
    }

    /// Seed the database with activities, tags, and backdated sessions.
    ///
    /// Activities are assigned 1-3 tags each. Sessions are distributed
    /// deterministically across ``daysSpan`` days with varying durations
    /// (15-104 minutes) and mixed types (work, timebound, rhythm).
    func seed(
        activityCount: Int = defaultActivityCount,
        sessionCount: Int = defaultSessionCount,
        tagCount: Int = defaultTagCount
    ) async throws {
        let calendar = Calendar.current
        let now = Date()

        // 1. Create tags
        for i in 1...tagCount {
            let tag = try await service.createTag(name: "Tag \(i)")
            if let id = tag.id {
                tagIds.append(id)
            }
        }

        // 2. Create activities with tag assignments
        for i in 1...activityCount {
            // Assign 1-3 tags deterministically per activity
            let tagCount = min(tagIds.count, 1 + (i % 3))
            let assignedTagIds = Array(tagIds.prefix(tagCount))

            let activity = try await service.createActivity(
                CreateActivityInput(title: "Benchmark Activity \(i)", tagIds: assignedTagIds)
            )
            if let id = activity.id {
                activityIds.append(id)
            }
        }

        // 3. Create backdated sessions spread across daysSpan days.
        //    Each day gets 2-hour time slots to prevent overlaps.
        //    Max duration is 104 minutes, which fits within a 2-hour slot.
        for i in 0..<sessionCount {
            let dayOffset = -(i % Self.daysSpan)
            let baseDate = calendar.date(byAdding: .day, value: dayOffset, to: now)
                ?? now
            let startOfDay = calendar.startOfDay(for: baseDate)

            // Each session gets a 2-hour slot. Max ~12 sessions per day.
            let slotOnDay = i / Self.daysSpan
            let slotStartSeconds = Double(slotOnDay) * 2 * 60 * 60
            let startedAt = startOfDay.addingTimeInterval(slotStartSeconds)

            let durationMinutes = 15 + (i % 90)  // 15-104 minutes, always < 120
            let endedAt = startedAt.addingTimeInterval(Double(durationMinutes) * 60)

            let activityId = activityIds[i % activityCount]
            let sessionType: SessionType = switch i % 5 {
            case 0: .rhythm
            case 1, 2: .timebound
            default: .work
            }

            _ = try await service.createBackdatedSession(CreateBackdatedSessionInput(
                activityId: activityId,
                sessionType: sessionType,
                startedAt: startedAt,
                endedAt: endedAt,
                timerLengthMinutes: sessionType == .work ? nil : durationMinutes,
                breakMinutes: sessionType == .rhythm ? 5 : nil
            ))
        }
    }
}
