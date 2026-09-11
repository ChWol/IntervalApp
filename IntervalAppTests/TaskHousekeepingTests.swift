import XCTest

@MainActor
final class TaskHousekeepingTests: XCTestCase {
    private var store: TestStore!
    private let now = TestTime.now
    
    override func setUp() async throws {
        try await super.setUp()
        store = try TestStore()
    }
    
    func testExpiredSelectsAgedCompletedAndBinnedTasks() {
        let oldCompleted = store.addTask("Done long ago",
                                         completed: true,
                                         id: "old-done",
                                         completedAt: now.addingTimeInterval(-TestTime.days(31)))
        let recentCompleted = store.addTask("Done yesterday",
                                            completed: true,
                                            id: "new-done",
                                            completedAt: now.addingTimeInterval(-TestTime.days(2)))
        let oldBinned = store.addTask("Trashed long ago",
                                      id: "old-bin",
                                      deletedAt: now.addingTimeInterval(-TestTime.days(40)))
        let active = store.addTask("Still going", id: "active")
        
        let expired = TaskHousekeeping.expired(from: [oldCompleted, recentCompleted, oldBinned, active], now: now)
        XCTAssertEqual(Set(expired.map(\.id)), Set([oldCompleted.id, oldBinned.id]))
    }
    
    func testMoveToBinSoftDeletesWithoutRemovingTheRow() throws {
        let task = store.addTask("Drop me", id: "t1")
        TaskHousekeeping.moveToBin(task, in: store.context, now: now)
        
        XCTAssertEqual(try store.tasks().count, 1)
        XCTAssertEqual(task.deletedAt, now)
        XCTAssertEqual(task.updatedAt, now)
    }

    func testCompletionAndSoftDeletePreserveTaskIdentityAndContent() throws {
        let task = store.addTask("A thought worth keeping", interval: "1 Month", order: 7, habitId: "habit-1", id: "task-1")

        HabitTaskLink.setTaskCompleted(true, on: task, now: now)
        TaskHousekeeping.moveToBin(task, in: store.context, now: now)

        let persisted = try XCTUnwrap(store.tasks().first { $0.id == "task-1" })
        XCTAssertEqual(persisted.text, "A thought worth keeping")
        XCTAssertEqual(persisted.intervalType, "1 Month")
        XCTAssertEqual(persisted.order, 7)
        XCTAssertEqual(persisted.habitId, "habit-1")
        XCTAssertTrue(persisted.completed)
        XCTAssertEqual(persisted.completedAt, now)
        XCTAssertEqual(persisted.deletedAt, now)
    }

    func testRetentionBoundaryDoesNotExpireTaskEarly() {
        let atBoundary = store.addTask(
            "Still retained",
            completed: true,
            id: "boundary",
            completedAt: now.addingTimeInterval(-TestTime.days(30))
        )

        XCTAssertFalse(TaskHousekeeping.expired(from: [atBoundary], now: now).contains { $0.id == atBoundary.id })
    }
    
    func testRestoreClearsBinAndCompletionAndUnticksLinkedHabit() throws {
        let habit = store.addHabit("Meditate", streak: 4, lastCompletedDate: now, id: "h1")
        let task = store.addTask("Meditate",
                                 interval: HabitTaskLink.hourInterval,
                                 completed: true,
                                 habitId: habit.id,
                                 id: "t1",
                                 deletedAt: now,
                                 completedAt: now)
        
        TaskHousekeeping.restore(task, in: store.context, now: now)
        
        XCTAssertNil(task.deletedAt)
        XCTAssertFalse(task.completed)
        XCTAssertNil(task.completedAt)
        XCTAssertFalse(habit.isCompleted(at: now))
        XCTAssertEqual(habit.streak, 3)
    }
    
    func testDeletePermanentlyRemovesLocalRows() throws {
        let a = store.addTask("A", id: "a")
        let b = store.addTask("B", id: "b")
        try store.save()
        
        TaskHousekeeping.deletePermanently([a, b], in: store.context)
        XCTAssertTrue(try store.tasks().isEmpty)
    }
    
    func testCompletedAndBinnedFilters() {
        let done = store.addTask("Done", completed: true, id: "done", completedAt: now)
        let binned = store.addTask("Gone", id: "bin", deletedAt: now)
        let both = store.addTask("Done then binned",
                                 completed: true,
                                 id: "both",
                                 deletedAt: now,
                                 completedAt: now)
        let active = store.addTask("Live", id: "live")
        
        let all = [done, binned, both, active]
        XCTAssertEqual(TaskHousekeeping.completed(from: all).map(\.id), [done.id])
        XCTAssertEqual(Set(TaskHousekeeping.binned(from: all).map(\.id)), Set([binned.id, both.id]))
    }
}
