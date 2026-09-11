import Foundation
import SwiftData

@MainActor
enum DataIntegrityRepair {
    static let validIntervals = Set(["1 Hour", "1 Day", "1 Week", "1 Month", "1 Year"])

    /// Repairs fields that would otherwise hide records or make distinct rows
    /// collide during synchronization. No record or user-authored text is removed.
    @discardableResult
    static func repair(_ context: ModelContext) -> Bool {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<HabitItem>())) ?? []
        let lists = (try? context.fetch(FetchDescriptor<ScratchpadList>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<ScratchpadItem>())) ?? []
        var changed = false

        let emptyHabits = habits.filter { $0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let replacementHabitId = emptyHabits.count == 1 ? UUID().uuidString : nil
        for habit in emptyHabits {
            habit.id = replacementHabitId ?? UUID().uuidString
            habit.syncedAt = nil
            changed = true
        }

        let emptyLists = lists.filter { $0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let replacementListId = emptyLists.count == 1 ? UUID().uuidString : nil
        for list in emptyLists {
            list.id = replacementListId ?? UUID().uuidString
            list.syncedAt = nil
            changed = true
        }

        for task in tasks {
            if task.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                task.id = UUID().uuidString
                task.syncedAt = nil
                changed = true
            }
            if !validIntervals.contains(task.intervalType) {
                task.intervalType = "1 Day"
                task.updatedAt = Date()
                task.syncedAt = nil
                changed = true
            }
            if task.habitId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                task.habitId = replacementHabitId
                task.syncedAt = nil
                changed = true
            }
        }

        for item in items {
            if item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                item.id = UUID().uuidString
                item.syncedAt = nil
                changed = true
            }
            if item.listId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let replacementListId {
                item.listId = replacementListId
                item.syncedAt = nil
                changed = true
            }
        }

        return changed
    }

    static func safeInterval(_ value: String?) -> String {
        guard let value, validIntervals.contains(value) else { return "1 Day" }
        return value
    }
}
