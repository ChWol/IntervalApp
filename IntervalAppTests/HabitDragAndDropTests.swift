import XCTest
import SwiftData

/// Validates habit chip drag & drop into the 1 Hour Focus list.
@MainActor
final class HabitDragAndDropTests: XCTestCase {
    private var store: TestStore!
    private let now = TestTime.now
    
    override func setUp() async throws {
        try await super.setUp()
        store = try TestStore()
    }
    
    override func tearDown() async throws {
        HabitDragState.shared.reset()
        DragState.shared.reset()
        store = nil
        try await super.tearDown()
    }
    
    func testInsertHabitAtTopPositionsItFirst() throws {
        let habit = store.addHabit("Drink 2L Water", id: "h-water")
        let existing1 = store.addTask("Read Email", interval: "1 Hour", order: 0, id: "t-1")
        let existing2 = store.addTask("Fix Bug", interval: "1 Hour", order: 1, id: "t-2")
        try store.save()
        
        insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Hour", context: store.context)
        
        let hourTasks = try store.tasks().filter { $0.intervalType == "1 Hour" }
        XCTAssertEqual(hourTasks.count, 3)
        XCTAssertEqual(hourTasks[0].habitId, habit.id)
        XCTAssertEqual(hourTasks[0].text, "Drink 2L Water")
        XCTAssertEqual(hourTasks[0].order, 0)
        
        XCTAssertEqual(hourTasks[1].id, existing1.id)
        XCTAssertEqual(hourTasks[1].order, 1)
        
        XCTAssertEqual(hourTasks[2].id, existing2.id)
        XCTAssertEqual(hourTasks[2].order, 2)
        
        // Habit itself must still exist in habits store
        let habits = try store.habits()
        XCTAssertEqual(habits.count, 1)
        XCTAssertEqual(habits.first?.id, habit.id)
    }
    
    func testInsertHabitAtBottomPositionsItLast() throws {
        let habit = store.addHabit("Go Gym", id: "h-gym")
        let existing1 = store.addTask("Review PR", interval: "1 Hour", order: 0, id: "t-1")
        let existing2 = store.addTask("Write Tests", interval: "1 Hour", order: 1, id: "t-2")
        try store.save()
        
        insertHabitAsTask(habit: habit, at: .bottom, listTitle: "1 Hour", context: store.context)
        
        let hourTasks = try store.tasks().filter { $0.intervalType == "1 Hour" }
        XCTAssertEqual(hourTasks.count, 3)
        XCTAssertEqual(hourTasks[0].id, existing1.id)
        XCTAssertEqual(hourTasks[1].id, existing2.id)
        XCTAssertEqual(hourTasks[2].habitId, habit.id)
        XCTAssertEqual(hourTasks[2].order, 2)
    }
    
    func testInsertHabitAtSpecificIndexPositionsCorrectly() throws {
        let habit = store.addHabit("Stretch", id: "h-stretch")
        let t0 = store.addTask("Task 0", interval: "1 Hour", order: 0, id: "t0")
        let t1 = store.addTask("Task 1", interval: "1 Hour", order: 1, id: "t1")
        let t2 = store.addTask("Task 2", interval: "1 Hour", order: 2, id: "t2")
        try store.save()
        
        insertHabitAsTask(habit: habit, at: .atIndex(1), listTitle: "1 Hour", context: store.context)
        
        let hourTasks = try store.tasks().filter { $0.intervalType == "1 Hour" }
        XCTAssertEqual(hourTasks.count, 4)
        XCTAssertEqual(hourTasks[0].id, t0.id)
        XCTAssertEqual(hourTasks[1].habitId, habit.id)
        XCTAssertEqual(hourTasks[1].order, 1)
        XCTAssertEqual(hourTasks[2].id, t1.id)
        XCTAssertEqual(hourTasks[2].order, 2)
        XCTAssertEqual(hourTasks[3].id, t2.id)
        XCTAssertEqual(hourTasks[3].order, 3)
    }
    
    func testInsertHabitIntoNonHourSectionIsIgnored() throws {
        let habit = store.addHabit("Language Lesson", id: "h-lang")
        try store.save()
        
        insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Day", context: store.context)
        insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Week", context: store.context)
        insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Month", context: store.context)
        insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Year", context: store.context)
        
        let tasks = try store.tasks()
        XCTAssertTrue(tasks.isEmpty, "Habits can ONLY be dropped into 1 Hour")
    }
    
    func testInsertHabitDoesNotDuplicateAlreadyPresentActiveHabitTask() throws {
        let habit = store.addHabit("Journal", id: "h-j")
        store.addTask("Journal", interval: "1 Hour", order: 0, habitId: habit.id, id: "t-j")
        try store.save()
        
        insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Hour", context: store.context)
        
        let hourTasks = try store.tasks().filter { $0.intervalType == "1 Hour" }
        XCTAssertEqual(hourTasks.count, 1, "Must not duplicate an active habit task in 1 Hour")
    }

    func testDragUsesSameHourIdentityAsTransition() throws {
        let habit = store.addHabit("Journal", id: "h-j")
        XCTAssertTrue(insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Hour", context: store.context))
        let dragged = try XCTUnwrap(store.tasks().first { $0.habitId == habit.id })
        XCTAssertEqual(dragged.id, HabitTaskLink.hourTaskId(habitId: habit.id, now: dragged.createdAt))
        XCTAssertTrue(HabitTaskLink.makeHourTasks(
            for: [habit], existingHourTasks: try store.tasks(), startingOrder: 1, now: dragged.createdAt
        ).isEmpty)
    }

    func testDragRelinksGeneratedTaskWhoseServerOmittedHabitId() throws {
        let habit = store.addHabit("Journal", id: "h-j")
        let taskId = HabitTaskLink.hourTaskId(habitId: habit.id, now: Date())
        store.addTask("Journal", interval: "1 Hour", id: taskId)
        try store.save()

        XCTAssertFalse(insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Hour", context: store.context))
        let tasks = try store.tasks()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.habitId, habit.id)
    }

    func testStartingTaskDragClearsAbandonedHabitDrag() throws {
        let habit = store.addHabit("Journal", id: "habit")
        let task = store.addTask("Real task", interval: "1 Day", order: 0, id: "task")
        HabitDragState.shared.begin(habit)
        HabitDragState.shared.targetIndex = 0
        HabitDragState.shared.isTargetingHour = true

        DragState.shared.begin(task, interval: "1 Day", fontSize: 20)

        XCTAssertNil(HabitDragState.shared.draggedHabit)
        XCTAssertNil(HabitDragState.shared.targetIndex)
        XCTAssertFalse(HabitDragState.shared.isTargetingHour)
        XCTAssertEqual(DragState.shared.draggedTask?.id, task.id)
    }

    func testStartingHabitDragClearsAbandonedTaskDrag() throws {
        let habit = store.addHabit("Journal", id: "habit")
        let task = store.addTask("Old task drag", interval: "1 Day", order: 0, id: "task")
        DragState.shared.begin(task, interval: "1 Hour", fontSize: 20)
        DragState.shared.targetIndex = 2

        HabitDragState.shared.begin(habit)

        XCTAssertNil(DragState.shared.draggedTask)
        XCTAssertNil(DragState.shared.targetIndex)
        XCTAssertEqual(HabitDragState.shared.draggedHabit?.id, habit.id)
    }

    func testMouseReleaseKeepsHabitAliveForSwiftUIDropHandoff() async throws {
        let habit = store.addHabit("Journal", id: "habit")
        HabitDragState.shared.begin(habit)

        HabitDragState.shared.resetAfterDropWindow()

        XCTAssertEqual(HabitDragState.shared.draggedHabit?.id, habit.id,
                       "Mouse-up must not erase the payload before performDrop runs")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(HabitDragState.shared.draggedHabit,
                     "A cancelled drag must still be cleared after the drop hand-off window")
    }

    func testVisibleInsertionSlotCreatesLinkedHourTask() throws {
        let habit = store.addHabit("Stretch", id: "stretch")
        store.addTask("First", interval: "1 Hour", order: 0)
        store.addTask("Last", interval: "1 Hour", order: 1)
        HabitDragState.shared.begin(habit)
        HabitDragState.shared.targetIndex = 1
        HabitDragState.shared.isTargetingHour = true

        XCTAssertTrue(TaskListInsertionDropDelegate.commitDrop(to: "1 Hour", at: 1, context: store.context))
        let ordered = try store.tasks().filter { $0.intervalType == "1 Hour" }.sorted { $0.order < $1.order }
        XCTAssertEqual(ordered.map(\.text), ["First", "Stretch", "Last"])
        XCTAssertEqual(ordered[1].habitId, habit.id)
        XCTAssertNil(HabitDragState.shared.draggedHabit)
    }

    func testRepeatedDropCallbacksDoNotCreateMultipleActiveHourTasks() throws {
        let habit = store.addHabit("Read", id: "read")
        HabitDragState.shared.begin(habit)

        XCTAssertTrue(TaskListInsertionDropDelegate.commitDrop(to: "1 Hour", at: 0, context: store.context))
        // A native drop can hand off through overlapping slot and row delegates.
        // Repeated callbacks must leave exactly one linked task.
        _ = TaskListInsertionDropDelegate.commitDrop(to: "1 Hour", at: 0, context: store.context)
        insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Hour", context: store.context)

        XCTAssertEqual(try store.tasks().filter {
            $0.habitId == habit.id && $0.intervalType == "1 Hour" && !$0.completed && $0.deletedAt == nil
        }.count, 1)
    }

    func testOneHabitDragCanClaimOnlyOneDrop() throws {
        let habit = store.addHabit("Read", id: "one-drop")
        HabitDragState.shared.begin(habit)

        XCTAssertTrue(HabitDragState.shared.claimDrop(for: habit))
        XCTAssertFalse(HabitDragState.shared.claimDrop(for: habit),
                       "Overlapping row and insertion-slot callbacks must not both insert")
    }

    func testCompletedLinkedTaskAllowsARealFutureInsertion() throws {
        let habit = store.addHabit("Read", id: "repeat-later")
        XCTAssertTrue(insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Hour", context: store.context))
        let first = try XCTUnwrap(store.tasks().first { $0.habitId == habit.id })
        XCTAssertFalse(insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Hour", context: store.context))

        first.completed = true
        XCTAssertTrue(insertHabitAsTask(habit: habit, at: .top, listTitle: "1 Hour", context: store.context))
        XCTAssertEqual(try store.tasks().filter { $0.habitId == habit.id && !$0.completed }.count, 1)
    }
}
