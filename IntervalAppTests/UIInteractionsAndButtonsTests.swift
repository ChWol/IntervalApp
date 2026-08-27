import XCTest
import SwiftData

/// Validates UI actions, button interactions, localization, and housekeeping routines.
@MainActor
final class UIInteractionsAndButtonsTests: XCTestCase {
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
    
    // MARK: - Housekeeping Buttons
    
    func testClearCompletedTasksOnlyPurgesCompletedNonHabitTasks() throws {
        let habit = store.addHabit("Habit Item", id: "h1")
        let habitTask = store.addTask("Habit Task", interval: "1 Hour", completed: true, habitId: habit.id, id: "ht1")
        let regularCompleted = store.addTask("Regular Task", interval: "1 Day", completed: true, id: "rt1")
        let regularActive = store.addTask("Active Task", interval: "1 Day", completed: false, id: "ra1")
        try store.save()
        
        let allTasks = try store.tasks()
        let toDelete = TaskHousekeeping.completed(from: allTasks)
        TaskHousekeeping.deletePermanently(toDelete, in: store.context)
        
        let remaining = try store.tasks()
        XCTAssertFalse(remaining.contains { $0.id == regularCompleted.id }, "Completed regular task was permanently cleared")
        XCTAssertTrue(remaining.contains { $0.id == regularActive.id }, "Active task must be preserved")
        XCTAssertTrue(remaining.contains { $0.id == habitTask.id }, "Habit task must NOT be wiped by clear completed button")
    }
    
    func testClearBinnedTasksOnlyPurgesBinnedNonHabitTasks() throws {
        let habit = store.addHabit("Habit Item 2", id: "h2")
        let habitTaskBinned = store.addTask("Habit Task 2", interval: "1 Hour", habitId: habit.id, id: "htb", deletedAt: now)
        let regularBinned = store.addTask("Regular Binned", interval: "1 Day", id: "rb", deletedAt: now)
        let regularActive = store.addTask("Active 2", interval: "1 Day", id: "ra2")
        try store.save()
        
        let allTasks = try store.tasks()
        let toDelete = TaskHousekeeping.binned(from: allTasks)
        TaskHousekeeping.deletePermanently(toDelete, in: store.context)
        
        let remaining = try store.tasks()
        XCTAssertFalse(remaining.contains { $0.id == regularBinned.id }, "Binned task was permanently cleared")
        XCTAssertTrue(remaining.contains { $0.id == regularActive.id }, "Active task must be preserved")
        XCTAssertTrue(remaining.contains { $0.id == habitTaskBinned.id }, "Habit task in bin must NOT be wiped by empty bin button")
    }
    
    // MARK: - Habit Postpone Button Interaction
    
    func testTogglePostponeForTodayTogglesState() throws {
        let habit = store.addHabit("Go Cycling", id: "h-cycle")
        XCTAssertFalse(habit.isPostponed(at: now))
        
        // Postpone for today
        habit.postponedDate = now
        habit.updatedAt = now
        XCTAssertTrue(habit.isPostponed(at: now))
        
        // Un-postpone
        habit.postponedDate = nil
        habit.updatedAt = now
        XCTAssertFalse(habit.isPostponed(at: now))
    }
    
    // MARK: - German and International Localization
    
    func testGermanLocalizationKeys() {
        LocalizationManager.shared.currentLanguage = .german
        
        XCTAssertEqual("RECENTLY DELETED".localized, "KÜRZLICH GELÖSCHT")
        XCTAssertEqual("BIN".localized, "KÜRZLICH GELÖSCHT")
        XCTAssertEqual("Empty Bin".localized, "Papierkorb leeren")
        XCTAssertEqual("COMPLETED".localized, "ERLEDIGT")
        XCTAssertEqual("HABITS".localized, "GEWOHNHEITEN")
        XCTAssertEqual("1 Hour".localized, "1 Stunde")
        XCTAssertEqual("1 Day".localized, "1 Tag")
        XCTAssertEqual("1 Week".localized, "1 Woche")
        XCTAssertEqual("1 Month".localized, "1 Monat")
        XCTAssertEqual("1 Year".localized, "1 Jahr")
        XCTAssertEqual("Clear All".localized, "Alle löschen")
    }
}
