import Foundation
import SwiftData
import XCTest

// Shared scaffolding for the test suites.
//
// How coding agents must use this testbench:
//   1. Run `xcodebuild test -scheme IntervalApp -destination "platform=macOS"` before AND after any changes.
//   2. All tests must pass (0 failures).
//   3. Tests strictly protect against data loss, phantom deletes, sync loops, and UI inconsistencies.

/// A throwaway SwiftData stack that lives only in memory, matching the app's full schema.
@MainActor
struct TestStore {
    let container: ModelContainer
    let context: ModelContext
    
    init() throws {
        container = try ModelContainer(
            for: TaskItem.self, HabitItem.self, ScratchpadList.self, ScratchpadItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }
    
    @discardableResult
    func addTask(_ text: String,
                 interval: String = "1 Day",
                 order: Int = 0,
                 completed: Bool = false,
                 habitId: String? = nil,
                 id: String? = nil,
                 updatedAt: Date? = nil,
                 syncedAt: Date? = nil,
                 deletedAt: Date? = nil,
                 completedAt: Date? = nil) -> TaskItem {
        let task = TaskItem(text: text, intervalType: interval, order: order, habitId: habitId)
        if let id { task.id = id }
        task.completed = completed
        task.completedAt = completedAt ?? (completed ? Date() : nil)
        task.deletedAt = deletedAt
        if let updatedAt { task.updatedAt = updatedAt }
        task.syncedAt = syncedAt
        context.insert(task)
        return task
    }
    
    @discardableResult
    func addHabit(_ text: String,
                  frequency: String = "Daily",
                  order: Int = 0,
                  streak: Int = 0,
                  lastCompletedDate: Date? = nil,
                  postponedDate: Date? = nil,
                  id: String? = nil,
                  updatedAt: Date? = nil,
                  syncedAt: Date? = nil,
                  deletedAt: Date? = nil) -> HabitItem {
        let habit = HabitItem(text: text, frequency: frequency, order: order)
        if let id { habit.id = id }
        habit.streak = streak
        habit.lastCompletedDate = lastCompletedDate
        habit.postponedDate = postponedDate
        habit.deletedAt = deletedAt
        if let updatedAt { habit.updatedAt = updatedAt }
        habit.syncedAt = syncedAt
        context.insert(habit)
        return habit
    }
    
    @discardableResult
    func addScratchpadList(_ title: String,
                           order: Int = 0,
                           id: String? = nil,
                           updatedAt: Date? = nil,
                           deletedAt: Date? = nil) -> ScratchpadList {
        let list = ScratchpadList(title: title, order: order)
        if let id { list.id = id }
        list.deletedAt = deletedAt
        if let updatedAt { list.updatedAt = updatedAt }
        context.insert(list)
        return list
    }
    
    @discardableResult
    func addScratchpadItem(_ text: String,
                           listId: String,
                           order: Int = 0,
                           completed: Bool = false,
                           id: String? = nil,
                           updatedAt: Date? = nil,
                           deletedAt: Date? = nil) -> ScratchpadItem {
        let item = ScratchpadItem(listId: listId, text: text, order: order)
        if let id { item.id = id }
        item.completed = completed
        item.deletedAt = deletedAt
        if let updatedAt { item.updatedAt = updatedAt }
        context.insert(item)
        return item
    }
    
    func save() throws {
        try context.save()
    }
    
    func tasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.order)]))
    }
    
    func habits() throws -> [HabitItem] {
        try context.fetch(FetchDescriptor<HabitItem>(sortBy: [SortDescriptor(\.order)]))
    }
    
    func scratchpadLists() throws -> [ScratchpadList] {
        try context.fetch(FetchDescriptor<ScratchpadList>(sortBy: [SortDescriptor(\.order)]))
    }
    
    func scratchpadItems() throws -> [ScratchpadItem] {
        try context.fetch(FetchDescriptor<ScratchpadItem>(sortBy: [SortDescriptor(\.order)]))
    }
}

/// A fixed instant, so tests never depend on the wall clock.
enum TestTime {
    /// 2026-06-15 12:00:00 UTC (Monday)
    static let now = Date(timeIntervalSince1970: 1_781_524_800)
    
    static func offset(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(seconds)
    }
    
    static func days(_ count: Double) -> TimeInterval {
        count * 86_400
    }
}
