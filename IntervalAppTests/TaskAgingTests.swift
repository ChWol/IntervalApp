import XCTest
import SwiftData
@testable import IntervalApp

@MainActor
final class TaskAgingTests: XCTestCase {
    private var store: TestStore!
    private var manager: MigrationManager!
    private let baseDate = Date(timeIntervalSince1970: 1700000000) // Fixed reference timestamp
    
    override func setUp() async throws {
        try await super.setUp()
        store = try TestStore()
        manager = MigrationManager()
        manager.attachForTesting(context: store.context)
    }
    
    override func tearDown() async throws {
        manager = nil
        store = nil
        try await super.tearDown()
    }
    
    // MARK: - Task Aging Threshold Rules
    
    func testHourTaskAgingThreshold() {
        let task = TaskItem(text: "Quick fix", intervalType: "1 Hour", order: 0)
        task.createdAt = baseDate
        
        // 2 hours 59 minutes: not lingering yet
        let before3h = baseDate.addingTimeInterval(3 * 3600 - 60)
        XCTAssertFalse(TaskAgingHelper.isLingering(task, at: before3h))
        
        // Exactly 3 hours: qualifies as lingering
        let at3h = baseDate.addingTimeInterval(3 * 3600)
        XCTAssertTrue(TaskAgingHelper.isLingering(task, at: at3h))
        
        // 4 hours: qualifies as lingering
        let at4h = baseDate.addingTimeInterval(4 * 3600)
        XCTAssertTrue(TaskAgingHelper.isLingering(task, at: at4h))
    }
    
    func testDayTaskAgingThreshold() {
        let task = TaskItem(text: "Daily goal", intervalType: "1 Day", order: 0)
        task.createdAt = baseDate
        
        // 1 day 23 hours: not lingering
        let before2d = baseDate.addingTimeInterval(2 * 86400 - 3600)
        XCTAssertFalse(TaskAgingHelper.isLingering(task, at: before2d))
        
        // 2 days: qualifies as lingering
        let at2d = baseDate.addingTimeInterval(2 * 86400)
        XCTAssertTrue(TaskAgingHelper.isLingering(task, at: at2d))
    }
    
    func testWeekTaskAgingThreshold() {
        let task = TaskItem(text: "Weekly project", intervalType: "1 Week", order: 0)
        task.createdAt = baseDate
        
        // 13 days: not lingering
        let before14d = baseDate.addingTimeInterval(13 * 86400)
        XCTAssertFalse(TaskAgingHelper.isLingering(task, at: before14d))
        
        // 14 days (2 weeks): qualifies as lingering
        let at14d = baseDate.addingTimeInterval(14 * 86400)
        XCTAssertTrue(TaskAgingHelper.isLingering(task, at: at14d))
    }
    
    func testMonthTaskAgingThreshold() {
        let task = TaskItem(text: "Monthly milestone", intervalType: "1 Month", order: 0)
        task.createdAt = baseDate
        
        // 89 days: not lingering
        let before90d = baseDate.addingTimeInterval(89 * 86400)
        XCTAssertFalse(TaskAgingHelper.isLingering(task, at: before90d))
        
        // 90 days (3 months): qualifies as lingering
        let at90d = baseDate.addingTimeInterval(90 * 86400)
        XCTAssertTrue(TaskAgingHelper.isLingering(task, at: at90d))
    }
    
    // MARK: - Habit & Invariant Isolation
    
    func testHabitTasksNeverQualifyAsLingering() {
        let habitTask = TaskItem(text: "Drink water", intervalType: "1 Hour", order: 0, habitId: "habit-123")
        habitTask.createdAt = baseDate
        
        // Even after 10 hours, habit tasks must never be demoted
        let future = baseDate.addingTimeInterval(10 * 3600)
        XCTAssertFalse(TaskAgingHelper.isLingering(habitTask, at: future))
    }
    
    func testCompletedAndDeletedTasksNeverQualifyAsLingering() {
        let completedTask = TaskItem(text: "Done task", intervalType: "1 Hour", order: 0)
        completedTask.createdAt = baseDate
        completedTask.completed = true
        
        let deletedTask = TaskItem(text: "Deleted task", intervalType: "1 Hour", order: 1)
        deletedTask.createdAt = baseDate
        deletedTask.deletedAt = baseDate.addingTimeInterval(3600)
        
        let future = baseDate.addingTimeInterval(10 * 3600)
        XCTAssertFalse(TaskAgingHelper.isLingering(completedTask, at: future))
        XCTAssertFalse(TaskAgingHelper.isLingering(deletedTask, at: future))
    }
    
    // MARK: - Migration Schedule with Reverse Tasks
    
    func testMigrationPresentsWhenOnlyReverseLingeringTasksExist() {
        let migration = Migration(source: "1 Day", dest: "1 Hour")
        
        // When source tasks and habits are empty, but reverse tasks exist -> should present!
        XCTAssertTrue(MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 0, reverseTaskCount: 2))
        
        // When completely empty -> do not present
        XCTAssertFalse(MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 0, reverseTaskCount: 0))
    }
    
    // MARK: - Reverse Demotion Execution
    
    func testExecuteMigrationMovesSelectedReverseTasksToParentInterval() {
        // Setup: A lingering task in 1 Hour (created 4 hours ago) and a fresh task in 1 Day
        let hourTask = TaskItem(text: "Lingering hour task", intervalType: "1 Hour", order: 0)
        hourTask.createdAt = baseDate.addingTimeInterval(-4 * 3600)
        store.context.insert(hourTask)
        
        let unselectedHourTask = TaskItem(text: "Stay in hour task", intervalType: "1 Hour", order: 1)
        store.context.insert(unselectedHourTask)
        
        let dayTask = TaskItem(text: "Day task to move forward", intervalType: "1 Day", order: 0)
        store.context.insert(dayTask)
        
        try? store.context.save()
        
        let migration = Migration(source: "1 Day", dest: "1 Hour")
        
        // Execute: Move dayTask -> 1 Hour AND reverse-demote hourTask -> 1 Day
        manager.executeMigration(
            migration: migration,
            selectedTaskIds: [dayTask.id],
            selectedHabitIds: [],
            selectedReverseTaskIds: [hourTask.id]
        )
        
        // Verify dayTask moved forward to 1 Hour
        XCTAssertEqual(dayTask.intervalType, "1 Hour")
        
        // Verify hourTask demoted backward to 1 Day
        XCTAssertEqual(hourTask.intervalType, "1 Day")
        
        // Verify unselected task remained safely in 1 Hour (Zero Data Loss invariant)
        XCTAssertEqual(unselectedHourTask.intervalType, "1 Hour")
        XCTAssertFalse(unselectedHourTask.completed)
        XCTAssertNil(unselectedHourTask.deletedAt)
    }
}
