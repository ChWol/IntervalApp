import XCTest

/// End-to-end hourly progression: picking day tasks and habits into the hour list.
@MainActor
final class MigrationManagerTests: XCTestCase {
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
    
    func testHourMigrationMovesSelectedDayTasksAndCreatesHabitTasks() throws {
        let dayA = store.addTask("Write report", interval: "1 Day", order: 0, id: "day-a")
        let dayB = store.addTask("Call bank", interval: "1 Day", order: 1, id: "day-b")
        let habit = store.addHabit("Meditate", order: 0, id: "habit-a")
        try store.save()
        
        let migration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        manager.executeMigration(
            migration: migration,
            selectedTaskIds: [dayA.id],
            selectedHabitIds: [habit.id]
        )
        
        let tasks = try store.tasks()
        let moved = try XCTUnwrap(tasks.first { $0.id == dayA.id })
        XCTAssertEqual(moved.intervalType, HabitTaskLink.hourInterval)
        
        let leftBehind = try XCTUnwrap(tasks.first { $0.id == dayB.id })
        XCTAssertEqual(leftBehind.intervalType, "1 Day",
                       "Unselected day tasks must stay on the day list")
        
        let fromHabit = try XCTUnwrap(tasks.first { $0.habitId == habit.id })
        XCTAssertEqual(fromHabit.text, "Meditate")
        XCTAssertEqual(fromHabit.intervalType, HabitTaskLink.hourInterval)
        XCTAssertNil(manager.currentMigration)
    }
    
    func testHourMigrationDoesNotDuplicateAnAlreadyListedHabit() throws {
        let habit = store.addHabit("Meditate", id: "habit-a")
        store.addTask("Meditate", interval: HabitTaskLink.hourInterval, order: 0, habitId: habit.id, id: "existing")
        try store.save()
        
        manager.executeMigration(
            migration: Migration(source: "1 Day", dest: HabitTaskLink.hourInterval),
            selectedTaskIds: [],
            selectedHabitIds: [habit.id]
        )
        
        let linked = try store.tasks().filter { $0.habitId == habit.id && $0.deletedAt == nil }
        XCTAssertEqual(linked.count, 1)
    }
    
    func testHourMigrationIsWorthShowingWhenOnlyHabitsAreAvailable() {
        store.addHabit("Meditate", id: "habit-a")
        try? store.save()
        
        let shown = manager.presentForTesting(
            Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        )
        XCTAssertTrue(shown)
        XCTAssertNotNil(manager.currentMigration)
    }
    
    func testHourMigrationIsSkippedWhenNothingIsAvailable() {
        let shown = manager.presentForTesting(
            Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        )
        XCTAssertFalse(shown)
        XCTAssertNil(manager.currentMigration)
    }
    
    func testYearResetHardDeletesUnselectedGoals() throws {
        let keep = store.addTask("Ship the app", interval: "1 Year", order: 0, id: "keep")
        let drop = store.addTask("Learn piano", interval: "1 Year", order: 1, id: "drop")
        try store.save()
        
        manager.executeMigration(
            migration: Migration(source: "1 Year", dest: "1 Year"),
            selectedTaskIds: [keep.id],
            selectedHabitIds: []
        )
        
        let remaining = try store.tasks().map(\.id)
        XCTAssertEqual(remaining, [keep.id])
        XCTAssertFalse(remaining.contains(drop.id))
    }
    
    func testSkippingDayMigrationHandsOffToFirstHourOfDay() throws {
        store.addTask("Plan the day", interval: "1 Day", order: 0)
        try store.save()
        
        manager.currentMigration = Migration(source: "1 Week", dest: "1 Day")
        manager.skipMigration()
        
        XCTAssertEqual(manager.currentMigration?.source, "1 Day")
        XCTAssertEqual(manager.currentMigration?.dest, HabitTaskLink.hourInterval)
        XCTAssertEqual(manager.currentMigration?.isFirstHourOfDay, true)
    }
}
