import Foundation
import SwiftData

/// The lifecycle of a task: into the bin, back out again, and eventually gone for good.
/// Kept in one place so every entry point behaves identically and so the rules can be tested.
enum TaskHousekeeping {
    /// How long completed and binned tasks are kept before they are removed automatically.
    static let retentionDays = 30
    
    static func cutoff(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now
    }
    
    /// Tasks whose completion or deletion has aged out of the retention window.
    static func expired(from tasks: [TaskItem], now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        let limit = cutoff(now: now, calendar: calendar)
        return tasks.filter { task in
            if let deletedAt = task.deletedAt { return deletedAt < limit }
            if let completedAt = task.completedAt { return completedAt < limit }
            return false
        }
    }
    
    /// Completed tasks that are not already in the bin.
    static func completed(from tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { $0.completed && $0.deletedAt == nil }
    }
    
    static func binned(from tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { $0.deletedAt != nil }
    }
    
    /// Soft delete: the task moves to the bin and stays recoverable on every device.
    static func moveToBin(_ task: TaskItem,
                          in context: ModelContext,
                          now: Date = Date(),
                          sync: SupabaseSyncManager = .shared) {
        task.deletedAt = now
        task.updatedAt = now
        try? context.save()
        sync.push()
    }
    
    static func restore(_ task: TaskItem,
                        in context: ModelContext,
                        now: Date = Date(),
                        sync: SupabaseSyncManager = .shared) {
        task.deletedAt = nil
        task.completed = false
        task.completedAt = nil
        task.updatedAt = now
        // Restoring a completed habit-linked hour task also unticks the habit, so the two
        // sides cannot disagree after an undo.
        if task.habitId != nil,
           let habits = try? context.fetch(FetchDescriptor<HabitItem>()) {
            HabitTaskLink.applyTaskCompletionToHabit(task, habits: habits, now: now)
        }
        try? context.save()
        sync.push()
    }
    
    /// Hard delete. The remote delete is registered *before* the local row disappears, so a
    /// pull already in flight cannot bring it back and the delete is retried until the server
    /// confirms it.
    static func deletePermanently(_ tasks: [TaskItem],
                                  in context: ModelContext,
                                  sync: SupabaseSyncManager = .shared) {
        guard !tasks.isEmpty else { return }
        sync.deleteRemote(table: SyncTable.tasks, ids: tasks.map { $0.id })
        for task in tasks {
            context.delete(task)
        }
        try? context.save()
    }
}
