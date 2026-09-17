import XCTest
import SwiftData

/// End-to-end migration tests covering task transfer, habit creation, marker synchronization, and dismissal.
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

    func testSameHourTransitionActionDeliveredFourTimesCreatesOneHabitTask() throws {
        let habit = store.addHabit("Meditate", id: "habit-a")
        try store.save()
        let migration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        manager.currentMigration = migration

        manager.executeMigration(migration: migration, selectedTaskIds: [], selectedHabitIds: [habit.id])
        // The original dialog must remain consumed even if its callback is delivered
        // after that task has left the hour list.
        let inserted = try XCTUnwrap(store.tasks().first { $0.habitId == habit.id })
        inserted.intervalType = "1 Day"
        try store.save()
        for _ in 0..<3 {
            manager.executeMigration(migration: migration, selectedTaskIds: [], selectedHabitIds: [habit.id])
        }

        let tasks = try store.tasks().filter { $0.habitId == habit.id && $0.deletedAt == nil }
        XCTAssertEqual(tasks.count, 1)
        XCTAssertNil(manager.currentMigration)
    }
    
    func testSkipMigrationClearsCurrentMigration() {
        manager.currentMigration = Migration(source: "1 Week", dest: "1 Day")
        XCTAssertNotNil(manager.currentMigration)
        
        manager.skipMigration()
        XCTAssertNil(manager.currentMigration)
    }

    func testStaleHourTransitionIsRejectedBeforeItCanInsertHabit() throws {
        let habit = store.addHabit("Meditate", id: "stale-habit")
        let stale = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        manager.currentMigration = stale
        manager.setPendingMarkerForTesting(key: "lastHandledHourMarker_v2", value: "2000-01-01-00")

        XCTAssertFalse(manager.isCurrentMigrationFresh())
        manager.executeMigration(migration: stale, selectedTaskIds: [], selectedHabitIds: [habit.id])

        XCTAssertTrue(try store.tasks().filter { $0.habitId == habit.id }.isEmpty)
        XCTAssertNotEqual(manager.currentMigration?.id, stale.id)
    }

    func testMigrationRestoresPreviousHourHabitLinkInsteadOfInsertingAgain() throws {
        let habit = store.addHabit("Meditate", id: "restored-habit")
        let previousHour = Date().addingTimeInterval(-3600)
        let restored = store.addTask("Meditate", interval: HabitTaskLink.hourInterval,
                                     id: HabitTaskLink.hourTaskId(habitId: habit.id, now: previousHour))
        restored.createdAt = previousHour
        try store.save()

        manager.executeMigration(migration: Migration(source: "1 Day", dest: HabitTaskLink.hourInterval),
                                 selectedTaskIds: [], selectedHabitIds: [habit.id])

        XCTAssertEqual(try store.tasks().filter {
            $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed
        }.count, 1)
        XCTAssertEqual(restored.habitId, habit.id)
    }

    func testEscapeCallbackForOldTransitionCannotSkipReplacement() {
        let stale = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        let replacement = Migration(source: "1 Week", dest: "1 Day")
        manager.currentMigration = replacement

        manager.skipMigration(expectedMigrationId: stale.id)

        XCTAssertEqual(manager.currentMigration?.id, replacement.id)
    }
    
    func testApplyRemoteMarkersDismissesAlreadyHandledMigration() {
        let hourKey = "lastHandledHourMarker_v2"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let currentHour = formatter.string(from: Date())
        
        manager.currentMigration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        XCTAssertNotNil(manager.currentMigration)
        
        // Remote device completed this hour's migration
        manager.applyRemoteMarkers([hourKey: currentHour])
        
        XCTAssertNil(manager.currentMigration, "Active modal must be dismissed immediately when remote marker arrives")
    }

    func testWeekDayAndHourTransitionsAppearImmediatelyInOrder() throws {
        let defaults = UserDefaults.standard
        let keys = [
            "lastHandledYearMarker_v2", "lastHandledMonthMarker_v2",
            "lastHandledWeekMarker_v2", "lastHandledDayMarker_v2",
            "lastHandledHourMarker_v2", "dayStartHour", "dayStartMinute"
        ]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = saved[key] ?? nil { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }

        let date = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy"
        defaults.set(formatter.string(from: date), forKey: keys[0])
        formatter.dateFormat = "yyyy-MM"
        defaults.set(formatter.string(from: date), forKey: keys[1])
        defaults.set("previous-week", forKey: keys[2])
        defaults.set("previous-day", forKey: keys[3])
        defaults.set("previous-hour", forKey: keys[4])
        defaults.set(0, forKey: "dayStartHour")
        defaults.set(0, forKey: "dayStartMinute")

        store.addTask("This week", interval: "1 Month")
        store.addTask("Today", interval: "1 Week")
        store.addTask("Now", interval: "1 Day")
        try store.save()

        manager.checkMigrations()
        XCTAssertEqual(manager.currentMigration?.dest, "1 Week")
        manager.skipMigration()
        XCTAssertEqual(manager.currentMigration?.dest, "1 Day")
        manager.skipMigration()
        XCTAssertEqual(manager.currentMigration?.dest, "1 Hour")
    }
}
