import XCTest
import SwiftData

/// CRITICAL TEST SUITE: Data Loss Prevention & Regression Guard.
/// Every test in this file validates an invariant that MUST NEVER BE BROKEN.
/// If any test here fails, user data is at risk of loss, corruption, or unintended deletion.
@MainActor
final class DataLossPreventionTests: XCTestCase {
    private var store: TestStore!
    private var manager: MigrationManager!
    private let now = TestTime.now
    
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
    
    // MARK: - 1. Migration Non-Selected Tasks Must NOT Be Deleted
    
    func testDayToHourMigrationPreservesUnselectedTasksInSourceInterval() throws {
        let selected = store.addTask("Selected for Hour", interval: "1 Day", order: 0, id: "task-1")
        let unselectedA = store.addTask("Remain in Day A", interval: "1 Day", order: 1, id: "task-2")
        let unselectedB = store.addTask("Remain in Day B", interval: "1 Day", order: 2, id: "task-3")
        try store.save()
        
        let migration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        manager.executeMigration(
            migration: migration,
            selectedTaskIds: [selected.id],
            selectedHabitIds: []
        )
        
        let allTasks = try store.tasks()
        
        // Selected task moved to 1 Hour
        let movedTask = try XCTUnwrap(allTasks.first { $0.id == selected.id })
        XCTAssertEqual(movedTask.intervalType, HabitTaskLink.hourInterval)
        XCTAssertNil(movedTask.deletedAt, "Moved task must not be marked deleted")
        
        // Unselected tasks MUST stay in 1 Day and MUST NOT be deleted
        let remainingA = try XCTUnwrap(allTasks.first { $0.id == unselectedA.id })
        XCTAssertEqual(remainingA.intervalType, "1 Day", "Unselected task must stay in '1 Day'")
        XCTAssertNil(remainingA.deletedAt, "CRITICAL: Unselected task must NOT be sent to bin")
        XCTAssertFalse(remainingA.completed, "Unselected task must remain active")
        
        let remainingB = try XCTUnwrap(allTasks.first { $0.id == unselectedB.id })
        XCTAssertEqual(remainingB.intervalType, "1 Day", "Unselected task must stay in '1 Day'")
        XCTAssertNil(remainingB.deletedAt, "CRITICAL: Unselected task must NOT be sent to bin")
        XCTAssertFalse(remainingB.completed, "Unselected task must remain active")
    }
    
    func testWeekToDayMigrationPreservesUnselectedTasksInWeek() throws {
        let chosen = store.addTask("Focus Today", interval: "1 Week", order: 0, id: "week-1")
        let stayInWeek = store.addTask("Later this week", interval: "1 Week", order: 1, id: "week-2")
        try store.save()
        
        let migration = Migration(source: "1 Week", dest: "1 Day")
        manager.executeMigration(
            migration: migration,
            selectedTaskIds: [chosen.id],
            selectedHabitIds: []
        )
        
        let allTasks = try store.tasks()
        
        let moved = try XCTUnwrap(allTasks.first { $0.id == chosen.id })
        XCTAssertEqual(moved.intervalType, "1 Day")
        XCTAssertNil(moved.deletedAt)
        
        let remained = try XCTUnwrap(allTasks.first { $0.id == stayInWeek.id })
        XCTAssertEqual(remained.intervalType, "1 Week")
        XCTAssertNil(remained.deletedAt, "CRITICAL: Unselected week task must NOT be deleted")
    }
    
    func testMonthToWeekMigrationPreservesUnselectedTasksInMonth() throws {
        let chosen = store.addTask("Week Goal", interval: "1 Month", order: 0, id: "m-1")
        let stayInMonth = store.addTask("Month Goal 2", interval: "1 Month", order: 1, id: "m-2")
        try store.save()
        
        let migration = Migration(source: "1 Month", dest: "1 Week")
        manager.executeMigration(
            migration: migration,
            selectedTaskIds: [chosen.id],
            selectedHabitIds: []
        )
        
        let allTasks = try store.tasks()
        let remained = try XCTUnwrap(allTasks.first { $0.id == stayInMonth.id })
        XCTAssertEqual(remained.intervalType, "1 Month")
        XCTAssertNil(remained.deletedAt, "CRITICAL: Unselected month task must NOT be deleted")
    }
    
    func testYearToMonthMigrationPreservesUnselectedTasksInYear() throws {
        let chosen = store.addTask("Month Focus", interval: "1 Year", order: 0, id: "y-1")
        let stayInYear = store.addTask("Annual Goal 2", interval: "1 Year", order: 1, id: "y-2")
        try store.save()
        
        let migration = Migration(source: "1 Year", dest: "1 Month")
        manager.executeMigration(
            migration: migration,
            selectedTaskIds: [chosen.id],
            selectedHabitIds: []
        )
        
        let allTasks = try store.tasks()
        let remained = try XCTUnwrap(allTasks.first { $0.id == stayInYear.id })
        XCTAssertEqual(remained.intervalType, "1 Year")
        XCTAssertNil(remained.deletedAt, "CRITICAL: Unselected year task must NOT be deleted")
    }
    
    // MARK: - 2. Transferred Habit Tasks Must NOT Pollute Bottom Lists
    
    func testCompletedHabitTaskExcludedFromCompletedList() throws {
        let habit = store.addHabit("Daily Workout", id: "habit-1")
        let habitTask = store.addTask("Daily Workout", interval: "1 Hour", completed: true, habitId: habit.id, id: "ht-1", completedAt: now)
        let regularTask = store.addTask("Buy groceries", interval: "1 Day", completed: true, id: "reg-1", completedAt: now)
        try store.save()
        
        let all = [habitTask, regularTask]
        let completed = TaskHousekeeping.completed(from: all)
        
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.id, regularTask.id, "Only regular non-habit tasks appear in Completed section")
        XCTAssertFalse(completed.contains { $0.id == habitTask.id }, "Habit tasks must NOT appear in bottom Completed section")
    }
    
    func testDeletedHabitTaskExcludedFromBinnedList() throws {
        let habit = store.addHabit("Drink Water", id: "habit-2")
        let habitTask = store.addTask("Drink Water", interval: "1 Hour", habitId: habit.id, id: "ht-2", deletedAt: now)
        let regularTask = store.addTask("Old Note", interval: "1 Day", id: "reg-2", deletedAt: now)
        try store.save()
        
        let all = [habitTask, regularTask]
        let binned = TaskHousekeeping.binned(from: all)
        
        XCTAssertEqual(binned.count, 1)
        XCTAssertEqual(binned.first?.id, regularTask.id, "Only regular non-habit tasks appear in Bin section")
        XCTAssertFalse(binned.contains { $0.id == habitTask.id }, "Habit tasks must NOT appear in bottom Bin section")
    }
    
    // MARK: - 3. Postponed Habits Must NOT Trigger or Appear in Hour Transitions
    
    func testPostponedHabitIsExcludedFromHourlySelectableHabits() throws {
        let activeHabit = store.addHabit("Read 10 pages", order: 0, id: "h-active")
        let postponedHabit = store.addHabit("Go for a run", order: 1, postponedDate: now, id: "h-postponed")
        try store.save()
        
        XCTAssertTrue(postponedHabit.isPostponed(at: now))
        
        let selectable = HabitTaskLink.selectableHabits(
            from: try store.habits(),
            hourTasks: try store.tasks(),
            now: now
        )
        
        XCTAssertEqual(selectable.map(\.id), [activeHabit.id])
        XCTAssertFalse(selectable.contains { $0.id == postponedHabit.id },
                       "Postponed habits must NOT appear in hourly transitions")
    }
    
    // MARK: - 4. Soft Delete & Restore Integrity
    
    func testSoftDeletePreservesTextAndOrder() throws {
        let task = store.addTask("Important Project Task", interval: "1 Week", order: 3, id: "task-p")
        TaskHousekeeping.moveToBin(task, in: store.context, now: now)
        
        XCTAssertEqual(task.text, "Important Project Task")
        XCTAssertEqual(task.intervalType, "1 Week")
        XCTAssertEqual(task.order, 3)
        XCTAssertEqual(task.deletedAt, now)
    }
    
    func testRestoreReturnsTaskToOriginalStateAndUnticksLinkedHabit() throws {
        let habit = store.addHabit("Meditation", streak: 5, lastCompletedDate: now, id: "h-med")
        let task = store.addTask("Meditation", interval: "1 Hour", completed: true, habitId: habit.id, id: "t-med", deletedAt: now, completedAt: now)
        try store.save()
        
        TaskHousekeeping.restore(task, in: store.context, now: now)
        
        XCTAssertNil(task.deletedAt, "Restore must clear deletedAt")
        XCTAssertFalse(task.completed, "Restore must reset completed to false")
        XCTAssertNil(task.completedAt, "Restore must clear completedAt")
        XCTAssertFalse(habit.isCompleted(at: now), "Restoring an hour habit task must un-tick the habit")
        XCTAssertEqual(habit.streak, 4, "Restoring must decrement streak if habit was completed today")
    }
    
    // MARK: - 5. Habit Target Weekday Setter Updates Timestamp for Sync
    
    func testHabitTargetWeekdaySetterUpdatesUpdatedAt() throws {
        let habit = store.addHabit("Weekly Review", frequency: "Weekly", id: "h-w", updatedAt: now.addingTimeInterval(-100))
        let oldUpdatedAt = habit.updatedAt
        
        habit.targetWeekday = 2 // Monday
        
        XCTAssertTrue(habit.updatedAt > oldUpdatedAt, "Modifying targetWeekday MUST update updatedAt so change is synced")
        XCTAssertEqual(habit.frequency, "Weekly:2")
    }
}
