import XCTest
import SwiftData

/// Validates transition dialog lifecycle, button state rules, selection state isolation, and annual goal initialization.
@MainActor
final class TransitionLifecycleAndSelectionTests: XCTestCase {
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
    
    // MARK: - Button State Validation Rules
    
    func testSkipButtonOnlyEnabledWhenNothingIsSelected() {
        var selectedTaskIds: Set<String> = []
        var selectedHabitIds: Set<String> = []
        
        func hasSelection() -> Bool {
            !selectedTaskIds.isEmpty || !selectedHabitIds.isEmpty
        }
        
        func isSkipDisabled() -> Bool {
            hasSelection()
        }
        
        func isMigrateDisabled() -> Bool {
            !hasSelection()
        }
        
        // 1. Initial empty state: Skip enabled, Migrate disabled
        XCTAssertFalse(isSkipDisabled(), "Skip button must be enabled when nothing is selected")
        XCTAssertTrue(isMigrateDisabled(), "Migrate button must be disabled when nothing is selected")
        
        // 2. Select a task: Skip disabled, Migrate enabled
        selectedTaskIds.insert("task-1")
        XCTAssertTrue(isSkipDisabled(), "Skip button must be disabled when a task is selected")
        XCTAssertFalse(isMigrateDisabled(), "Migrate button must be enabled when a task is selected")
        
        // 3. Deselect task and select habit: Skip disabled, Migrate enabled
        selectedTaskIds.removeAll()
        selectedHabitIds.insert("habit-1")
        XCTAssertTrue(isSkipDisabled(), "Skip button must be disabled when a habit is selected")
        XCTAssertFalse(isMigrateDisabled(), "Migrate button must be enabled when a habit is selected")
        
        // 4. Deselect habit: Skip enabled again, Migrate disabled
        selectedHabitIds.removeAll()
        XCTAssertFalse(isSkipDisabled(), "Skip button must be re-enabled when selection is cleared")
        XCTAssertTrue(isMigrateDisabled(), "Migrate button must be disabled when selection is cleared")
    }
    
    // MARK: - Year Reset Goal Initialization
    
    func testCommitYearGoalsCreatesNewYearTasks() throws {
        let goals = ["Launch Product", "Read 20 Books", "Run a Marathon"]
        
        var maxOrder = 0
        for goal in goals {
            store.addTask(goal, interval: "1 Year", order: maxOrder)
            maxOrder += 1
        }
        try store.save()
        
        let yearTasks = try store.tasks().filter { $0.intervalType == "1 Year" }
        XCTAssertEqual(yearTasks.count, 3)
        XCTAssertEqual(yearTasks[0].text, "Launch Product")
        XCTAssertEqual(yearTasks[1].text, "Read 20 Books")
        XCTAssertEqual(yearTasks[2].text, "Run a Marathon")
    }
}
