import XCTest

/// The hourly migration's habit↔task contract. Agents debugging streak or tick bugs should
/// start here: every rule is pure and runs against an in-memory store.
@MainActor
final class HabitTaskLinkTests: XCTestCase {
    private var store: TestStore!
    private let now = TestTime.now
    
    override func setUp() async throws {
        try await super.setUp()
        store = try TestStore()
    }
    
    // MARK: - Selection

    func testRepeatedSelectedHabitCreatesOnlyOneHourTask() throws {
        let habit = store.addHabit("Meditate", id: "habit-once")
        let created = HabitTaskLink.makeHourTasks(
            for: [habit, habit, habit],
            existingHourTasks: [],
            startingOrder: 0,
            now: now
        )
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.habitId, habit.id)
    }

    func testSelectableHabitsDeduplicatesRepeatedHabitRows() {
        let habit = store.addHabit("Meditate", id: "habit-once")
        let selectable = HabitTaskLink.selectableHabits(
            from: [habit, habit], hourTasks: [], now: now
        )
        XCTAssertEqual(selectable.map(\.id), [habit.id])
    }
    
    func testSelectableHabitsSkipDeletedCompletedPostponedAndAlreadyListed() throws {
        let open = store.addHabit("Meditate", order: 0, id: "h-open")
        let done = store.addHabit("Run", order: 1, lastCompletedDate: now, id: "h-done")
        let deleted = store.addHabit("Journal", order: 2, id: "h-gone", deletedAt: now)
        let postponed = store.addHabit("Gym", order: 3, postponedDate: now, id: "h-postponed")
        let listed = store.addHabit("Stretch", order: 4, id: "h-listed")
        store.addTask("Stretch", interval: HabitTaskLink.hourInterval, habitId: listed.id, id: "t-listed")
        
        let selectable = HabitTaskLink.selectableHabits(
            from: try store.habits(),
            hourTasks: try store.tasks(),
            now: now
        )
        
        XCTAssertEqual(selectable.map(\.id), [open.id])
        XCTAssertFalse(selectable.contains { $0.id == done.id })
        XCTAssertFalse(selectable.contains { $0.id == deleted.id })
        XCTAssertFalse(selectable.contains { $0.id == postponed.id })
        XCTAssertFalse(selectable.contains { $0.id == listed.id })
    }
    
    func testMakeHourTasksCreatesLinkedRowsAndSkipsDuplicates() throws {
        let a = store.addHabit("Meditate", order: 0, id: "h-a")
        let b = store.addHabit("Run", order: 1, id: "h-b")
        store.addTask("Meditate", interval: HabitTaskLink.hourInterval, order: 0, habitId: a.id)
        
        let created = HabitTaskLink.makeHourTasks(
            for: [a, b],
            existingHourTasks: try store.tasks(),
            startingOrder: 1,
            now: now
        )
        
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created[0].habitId, b.id)
        XCTAssertEqual(created[0].text, "Run")
        XCTAssertEqual(created[0].intervalType, HabitTaskLink.hourInterval)
        XCTAssertEqual(created[0].order, 1)
    }
    
    func testMakeHourTasksIgnoresBlankHabitNames() {
        let blank = HabitItem(text: "   ", order: 0)
        blank.id = "blank"
        let created = HabitTaskLink.makeHourTasks(for: [blank], existingHourTasks: [], startingOrder: 0, now: now)
        XCTAssertTrue(created.isEmpty)
    }
    
    // MARK: - Completion mirroring
    
    func testTickingHourTaskTicksTheHabitAndIncrementsStreak() throws {
        let habit = store.addHabit("Meditate", streak: 2, id: "h1")
        let task = store.addTask("Meditate", interval: HabitTaskLink.hourInterval, habitId: habit.id, id: "t1")
        
        HabitTaskLink.setTaskCompleted(true, on: task, now: now)
        XCTAssertTrue(HabitTaskLink.applyTaskCompletionToHabit(task, habits: try store.habits(), now: now))
        
        XCTAssertTrue(habit.isCompleted(at: now))
        XCTAssertEqual(habit.streak, 3)
        XCTAssertEqual(habit.lastCompletedDate, now)
    }
    
    func testUntickingHourTaskUnticksTheHabitAndDecrementsStreak() throws {
        let habit = store.addHabit("Meditate", streak: 3, lastCompletedDate: now, id: "h1")
        let task = store.addTask("Meditate",
                                 interval: HabitTaskLink.hourInterval,
                                 completed: true,
                                 habitId: habit.id,
                                 id: "t1",
                                 completedAt: now)
        
        HabitTaskLink.setTaskCompleted(false, on: task, now: now)
        XCTAssertTrue(HabitTaskLink.applyTaskCompletionToHabit(task, habits: try store.habits(), now: now))
        
        XCTAssertFalse(habit.isCompleted(at: now))
        XCTAssertEqual(habit.streak, 2)
        XCTAssertNil(habit.lastCompletedDate)
    }
    
    func testTickingHabitCompletesItsHourTasks() throws {
        let habit = store.addHabit("Meditate", id: "h1")
        let task = store.addTask("Meditate", interval: HabitTaskLink.hourInterval, habitId: habit.id, id: "t1")
        
        HabitTaskLink.setHabitCompleted(true, on: habit, now: now)
        XCTAssertTrue(HabitTaskLink.applyHabitCompletionToTasks(habit, tasks: try store.tasks(), now: now))
        
        XCTAssertTrue(task.completed)
        XCTAssertEqual(task.completedAt, now)
    }
    
    func testUntickingHabitUnticksItsHourTasks() throws {
        let habit = store.addHabit("Meditate", lastCompletedDate: now, id: "h1")
        let task = store.addTask("Meditate",
                                 interval: HabitTaskLink.hourInterval,
                                 completed: true,
                                 habitId: habit.id,
                                 id: "t1",
                                 completedAt: now)
        
        HabitTaskLink.setHabitCompleted(false, on: habit, now: now)
        XCTAssertTrue(HabitTaskLink.applyHabitCompletionToTasks(habit, tasks: try store.tasks(), now: now))
        
        XCTAssertFalse(task.completed)
        XCTAssertNil(task.completedAt)
    }
    
    func testDoubleTickIsIdempotent() throws {
        let habit = store.addHabit("Meditate", streak: 1, id: "h1")
        HabitTaskLink.setHabitCompleted(true, on: habit, now: now)
        XCTAssertEqual(habit.streak, 2)
        XCTAssertFalse(HabitTaskLink.setHabitCompleted(true, on: habit, now: now),
                       "Ticking an already-done habit must not bump the streak again")
        XCTAssertEqual(habit.streak, 2)
    }

    func testCompletionHistoryIsDayUniqueAndSurvivesUntickingCurrentDay() {
        let habit = store.addHabit("Meditate", id: "h-history")
        let yesterday = now.addingTimeInterval(-86_400)

        XCTAssertTrue(HabitTaskLink.setHabitCompleted(true, on: habit, now: yesterday))
        XCTAssertTrue(HabitTaskLink.setHabitCompleted(true, on: habit, now: now))
        XCTAssertEqual(habit.completionDates.count, 2)

        // Repeating the same completion period must not create a duplicate dot
        // in the statistics calendar.
        XCTAssertFalse(HabitTaskLink.setHabitCompleted(true, on: habit, now: now))
        XCTAssertEqual(habit.completionDates.count, 2)

        XCTAssertTrue(HabitTaskLink.setHabitCompleted(false, on: habit, now: now))
        XCTAssertEqual(habit.completionDates.count, 1)
        XCTAssertEqual(habit.lastCompletedDate?.timeIntervalSince1970 ?? 0,
                       yesterday.timeIntervalSince1970,
                       accuracy: 0.01)
    }

    func testCompletionRaceUsesNewestLinkedTaskWithoutDoubleCountingStreak() throws {
        let habit = store.addHabit("Meditate", streak: 2, id: "h1", updatedAt: now)
        let task = store.addTask("Meditate", interval: HabitTaskLink.hourInterval,
                                 completed: true, habitId: habit.id, id: "t1",
                                 updatedAt: now.addingTimeInterval(10), completedAt: now.addingTimeInterval(10))

        XCTAssertTrue(HabitTaskLink.reconcileCompletion(tasks: [task], habits: [habit]))
        XCTAssertTrue(habit.isCompleted(at: task.updatedAt))
        XCTAssertEqual(habit.streak, 3)
        XCTAssertFalse(HabitTaskLink.reconcileCompletion(tasks: [task], habits: [habit]))
        XCTAssertEqual(habit.streak, 3)
    }

    func testCompletionRaceUsesNewestHabitForEveryLinkedTask() throws {
        let habitStamp = now.addingTimeInterval(20)
        let habit = store.addHabit("Meditate", streak: 1, lastCompletedDate: habitStamp,
                                   id: "h1", updatedAt: habitStamp)
        let task = store.addTask("Meditate", interval: HabitTaskLink.hourInterval,
                                 habitId: habit.id, id: "t1", updatedAt: now)

        XCTAssertTrue(HabitTaskLink.reconcileCompletion(tasks: [task], habits: [habit]))
        XCTAssertTrue(task.completed)
        XCTAssertEqual(task.completedAt, habitStamp)
        XCTAssertEqual(task.updatedAt, habitStamp)
    }
    
    func testDeletedHabitIsNotUpdatedByItsHourTask() throws {
        let habit = store.addHabit("Meditate", id: "h1", deletedAt: now)
        let task = store.addTask("Meditate", interval: HabitTaskLink.hourInterval, habitId: habit.id)
        HabitTaskLink.setTaskCompleted(true, on: task, now: now)
        
        XCTAssertFalse(HabitTaskLink.applyTaskCompletionToHabit(task, habits: try store.habits(), now: now))
        XCTAssertEqual(habit.streak, 0)
    }
    
    func testBinningLinkedHourTasksSoftDeletesActiveOnesOnly() throws {
        let habit = store.addHabit("Meditate", id: "h1")
        let live = store.addTask("Meditate", interval: HabitTaskLink.hourInterval, habitId: habit.id, id: "live")
        let done = store.addTask("Meditate",
                                 interval: HabitTaskLink.hourInterval,
                                 completed: true,
                                 habitId: habit.id,
                                 id: "done",
                                 completedAt: now)
        let other = store.addTask("Write", interval: HabitTaskLink.hourInterval, id: "other")
        
        let binned = HabitTaskLink.binLinkedHourTasks(for: habit, tasks: try store.tasks(), now: now)
        XCTAssertEqual(binned.map(\.id), [live.id])
        XCTAssertNotNil(live.deletedAt)
        XCTAssertNil(done.deletedAt)
        XCTAssertNil(other.deletedAt)
    }
}
