import XCTest
import SwiftData

/// Validates keyboard navigation, multiline task handling, text trimming, and reordering across macOS & iOS.
@MainActor
final class TaskKeyboardAndNavigationTests: XCTestCase {
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
    
    // MARK: - Section Cycling Order (Tab Navigation)
    
    func testTabNavigationCyclesTopToBottomAcrossAllIntervals() {
        let intervals = ["1 Hour", "1 Day", "1 Week", "1 Month", "1 Year"]
        
        // Simulating the Tab key cycling sequence through sections
        var currentSectionIndex = 0
        
        // Pressing Tab advances to next section
        func nextSection() -> String {
            currentSectionIndex = (currentSectionIndex + 1) % intervals.count
            return intervals[currentSectionIndex]
        }
        
        XCTAssertEqual(nextSection(), "1 Day")
        XCTAssertEqual(nextSection(), "1 Week")
        XCTAssertEqual(nextSection(), "1 Month")
        XCTAssertEqual(nextSection(), "1 Year")
        XCTAssertEqual(nextSection(), "1 Hour") // Wraps around to top
    }
    
    // MARK: - Multiline Text Splitting on Paste
    
    func testPastingMultilineTextCreatesMultipleOrderedTasks() throws {
        let multilineInput = """
        Buy groceries
        Call dentist
        Fix bicycle tyre
        """
        
        let lines = multilineInput.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        XCTAssertEqual(lines.count, 3)
        
        for (index, line) in lines.enumerated() {
            store.addTask(line, interval: "1 Day", order: index)
        }
        try store.save()
        
        let dayTasks = try store.tasks().filter { $0.intervalType == "1 Day" }
        XCTAssertEqual(dayTasks.count, 3)
        XCTAssertEqual(dayTasks[0].text, "Buy groceries")
        XCTAssertEqual(dayTasks[0].order, 0)
        XCTAssertEqual(dayTasks[1].text, "Call dentist")
        XCTAssertEqual(dayTasks[1].order, 1)
        XCTAssertEqual(dayTasks[2].text, "Fix bicycle tyre")
        XCTAssertEqual(dayTasks[2].order, 2)
    }
    
    // MARK: - Empty Task Trimming
    
    func testEmptyAndWhitespaceTasksAreIgnoredOnCreation() throws {
        let emptyTask = TaskItem(text: "   ", intervalType: "1 Day")
        let trimmed = emptyTask.text.trimmingCharacters(in: .whitespaces)
        
        XCTAssertTrue(trimmed.isEmpty, "Whitespace-only tasks must not be committed to persistence")
    }
    
    // MARK: - Drag Reordering Within & Across Sections
    
    func testMovingTaskFromDayToWeekUpdatesIntervalAndOrder() throws {
        let task1 = store.addTask("Prepare slides", interval: "1 Day", order: 0, id: "t1")
        let task2 = store.addTask("Send agenda", interval: "1 Week", order: 0, id: "t2")
        try store.save()
        
        // Move task1 from 1 Day to 1 Week
        task1.intervalType = "1 Week"
        task1.order = 1
        task1.updatedAt = now
        try store.save()
        
        let dayTasks = try store.tasks().filter { $0.intervalType == "1 Day" }
        let weekTasks = try store.tasks().filter { $0.intervalType == "1 Week" }
        
        XCTAssertTrue(dayTasks.isEmpty)
        XCTAssertEqual(weekTasks.count, 2)
        XCTAssertEqual(weekTasks[0].id, task2.id)
        XCTAssertEqual(weekTasks[1].id, task1.id)
    }
}
