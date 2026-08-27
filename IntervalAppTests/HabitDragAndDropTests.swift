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
}
