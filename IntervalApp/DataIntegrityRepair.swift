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
            habit.updatedAt = Date()
            habit.syncedAt = nil
            changed = true
        }

        let emptyLists = lists.filter { $0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let replacementListId = emptyLists.count == 1 ? UUID().uuidString : nil
        for list in emptyLists {
            list.id = replacementListId ?? UUID().uuidString
            list.updatedAt = Date()
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
                task.intervalEnteredAt = Date()
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

        // A single habit drag must produce one active hour task. Earlier builds
        // could deliver the same drop through overlapping row and slot targets.
        // Retain the oldest copy and soft-delete only identical burst copies;
        // differing user-edited text or older tasks remain untouched.
        let activeLinkedHourTasks = tasks.filter {
            $0.habitId != nil && $0.intervalType == HabitTaskLink.hourInterval
                && $0.deletedAt == nil && !$0.completed
        }
        let byHabit = Dictionary(grouping: activeLinkedHourTasks, by: { $0.habitId! })
        let repairTime = Date()
        for copies in byHabit.values where copies.count > 1 {
            let ordered = copies.sorted {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
            }
            guard let keeper = ordered.first else { continue }
            for duplicate in ordered.dropFirst()
            where duplicate.text == keeper.text
                && duplicate.createdAt.timeIntervalSince(keeper.createdAt) <= 600 {
                duplicate.deletedAt = repairTime
                duplicate.updatedAt = repairTime
                duplicate.syncedAt = nil
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

        // SwiftData does not enforce uniqueness for application ids. Preserve every
        // scratchpad record while giving colliding copies deterministic independent ids;
        // otherwise dictionary merges and batch upserts can silently discard one copy.
        let repairStamp = Date()
        for copies in Dictionary(grouping: lists, by: \ScratchpadList.id).values where copies.count > 1 {
            let ordered = copies.sorted {
                $0.updatedAt == $1.updatedAt ? $0.createdAt > $1.createdAt : $0.updatedAt > $1.updatedAt
            }
            for duplicate in ordered.dropFirst() {
                duplicate.id = UUID().uuidString
                duplicate.updatedAt = repairStamp
                duplicate.syncedAt = nil
                changed = true
            }
        }
        for copies in Dictionary(grouping: items, by: \ScratchpadItem.id).values where copies.count > 1 {
            let ordered = copies.sorted {
                $0.updatedAt == $1.updatedAt ? $0.createdAt > $1.createdAt : $0.updatedAt > $1.updatedAt
            }
            for duplicate in ordered.dropFirst() {
                duplicate.id = UUID().uuidString
                duplicate.updatedAt = repairStamp
                duplicate.syncedAt = nil
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
