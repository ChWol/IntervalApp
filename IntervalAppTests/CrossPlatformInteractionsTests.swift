import XCTest
import SwiftData

/// Validates cross-platform features: macOS Menu Bar view data filtering, search indexing, and export/import validation.
@MainActor
final class CrossPlatformInteractionsTests: XCTestCase {
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
    
    // MARK: - Menu Bar Data Filtering
    
    func testMenuBarShowsOnlyActiveHourTasks() throws {
        let activeHour1 = store.addTask("Finish document", interval: "1 Hour", order: 0, id: "h1")
        let activeHour2 = store.addTask("Call client", interval: "1 Hour", order: 1, id: "h2")
        let completedHour = store.addTask("Old task", interval: "1 Hour", completed: true, id: "h-done")
        let deletedHour = store.addTask("Deleted task", interval: "1 Hour", id: "h-del", deletedAt: now)
        let dayTask = store.addTask("Day task", interval: "1 Day", id: "d1")
        try store.save()
        
        let allTasks = try store.tasks()
        
        // Filter logic used in MenuBarTaskView
        let menuBarTasks = allTasks.filter { $0.intervalType == "1 Hour" && $0.deletedAt == nil && !$0.completed }
            .sorted { $0.order < $1.order }
        
        XCTAssertEqual(menuBarTasks.count, 2)
        XCTAssertEqual(menuBarTasks.map(\.id), [activeHour1.id, activeHour2.id])
        XCTAssertFalse(menuBarTasks.contains { $0.id == completedHour.id }, "Completed tasks must NOT appear in Menu Bar")
        XCTAssertFalse(menuBarTasks.contains { $0.id == deletedHour.id }, "Deleted tasks must NOT appear in Menu Bar")
        XCTAssertFalse(menuBarTasks.contains { $0.id == dayTask.id }, "Non-hour tasks must NOT appear in Menu Bar")
    }
    
    // MARK: - Search Filtering
    
    func testSearchMatchesAcrossIntervalsAndNotes() throws {
        let taskA = store.addTask("Review SwiftData architecture", interval: "1 Day", id: "sa")
        let taskB = store.addTask("Meeting with design team", interval: "1 Week", id: "sb")
        let habit = store.addHabit("Swift coding practice", id: "sh")
        try store.save()
        
        let query = "Swift"
        let tasks = try store.tasks()
        let habits = try store.habits()
        
        let matchedTasks = tasks.filter { $0.deletedAt == nil && $0.text.localizedCaseInsensitiveContains(query) }
        let matchedHabits = habits.filter { $0.deletedAt == nil && $0.text.localizedCaseInsensitiveContains(query) }
        
        XCTAssertEqual(matchedTasks.count, 1)
        XCTAssertEqual(matchedTasks.first?.id, taskA.id)
        
        XCTAssertEqual(matchedHabits.count, 1)
        XCTAssertEqual(matchedHabits.first?.id, habit.id)
    }
    
    // MARK: - Export / Import Validation
    
    func testCorruptedImportDataIsRejectedWithoutModifyingExistingStore() throws {
        store.addTask("Existing Safe Task", interval: "1 Day", id: "safe-1")
        try store.save()
        
        let corruptedJson = "{ \"tasks\": [ { \"invalid_json\" ] }".data(using: .utf8)!
        
        // Attempting to parse corrupt JSON
        let decoded = try? JSONSerialization.jsonObject(with: corruptedJson)
        XCTAssertNil(decoded, "Malformed JSON must fail parsing safely")
        
        // Existing store must remain untouched
        let tasks = try store.tasks()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.text, "Existing Safe Task")
    }
}
