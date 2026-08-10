import Foundation
import SwiftData
import XCTest

// Shared scaffolding for the test suites.
//
// How coding agents should use this suite:
//   1. Reproduce the bug with a failing test in the matching *Tests.swift file.
//   2. Fix the pure helper (`SyncCore`, `HabitTaskLink`, `MigrationSchedule`,
//      `TaskHousekeeping`) rather than papering over the UI.
//   3. Re-run `./scripts/run-tests.sh` (or see IntervalAppTests/README.md).
//
// The test bundle compiles the app's own sources, so tests call production types directly
// with no `@testable import` and no host application. Nothing here touches the network or
// the real database: `SupabaseSyncManager` stays unauthenticated in tests, which makes every
// one of its side effects a no-op.

/// A throwaway SwiftData stack that lives only in memory, matching the app's schema.
@MainActor
struct TestStore {
    let container: ModelContainer
    let context: ModelContext
    
    init() throws {
        container = try ModelContainer(
            for: TaskItem.self, HabitItem.self,
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
                  id: String? = nil,
                  updatedAt: Date? = nil,
                  syncedAt: Date? = nil,
                  deletedAt: Date? = nil) -> HabitItem {
        let habit = HabitItem(text: text, frequency: frequency, order: order)
        if let id { habit.id = id }
        habit.streak = streak
        habit.lastCompletedDate = lastCompletedDate
        habit.deletedAt = deletedAt
        if let updatedAt { habit.updatedAt = updatedAt }
        habit.syncedAt = syncedAt
        context.insert(habit)
        return habit
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
}

/// A fixed instant, so tests never depend on the wall clock.
enum TestTime {
    /// 2026-06-15 12:00:00 UTC
    static let now = Date(timeIntervalSince1970: 1_781_524_800)
    
    static func offset(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(seconds)
    }
    
    static func days(_ count: Double) -> TimeInterval {
        count * 86_400
    }
}
