import Foundation
import CryptoKit

/// Rules connecting habits to the hour tasks created from them during an hourly migration.
/// Ticking either side ticks the other, and streaks are counted exactly once per period.
enum HabitTaskLink {
    static let hourInterval = "1 Hour"

    /// Both devices must name the same hour's generated task identically. Otherwise
    /// simultaneous transitions create different rows that sync cannot recognize as one.
    static func hourTaskId(habitId: String, now: Date) -> String {
        let hour = Int(now.timeIntervalSince1970 / 3600)
        var bytes = Array(Insecure.SHA1.hash(data: Data("interval:habit-hour:\(habitId):\(hour)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )).uuidString
    }
    
    // MARK: - Selection
    
    /// Habits that can still be pulled into the coming hour: not deleted, not already done
    /// for the current period, and not already sitting in the hour list.
    static func selectableHabits(from habits: [HabitItem], hourTasks: [TaskItem], now: Date = Date()) -> [HabitItem] {
        var alreadyListed = Set(
            hourTasks
                .filter { $0.deletedAt == nil && !$0.completed }
                .compactMap { $0.habitId }
        )
        for task in hourTasks where task.deletedAt == nil && !task.completed && task.habitId == nil {
            for habit in habits where hourTaskId(habitId: habit.id, now: task.createdAt) == task.id {
                alreadyListed.insert(habit.id)
            }
        }
        var seenHabitIds = Set<String>()
        return habits
            .filter { $0.deletedAt == nil }
            .filter { $0.isScheduledForTodayOrOverdue(date: now) }
            .filter { !$0.isCompleted(at: now) }
            .filter { !$0.isPostponed(at: now) }
            .filter { !alreadyListed.contains($0.id) }
            .filter { seenHabitIds.insert($0.id).inserted }
            .sorted { h1, h2 in
                let o1 = h1.isOverdueInCurrentWeek(date: now)
                let o2 = h2.isOverdueInCurrentWeek(date: now)
                if o1 != o2 { return o1 && !o2 }
                return h1.order < h2.order
            }
    }
    
    /// Builds the hour tasks for the chosen habits, appended after `startingOrder`.
    /// A habit that already has a live hour task is skipped so repeated migrations cannot
    /// stack duplicates.
    static func makeHourTasks(for habits: [HabitItem], existingHourTasks: [TaskItem], startingOrder: Int, now: Date = Date()) -> [TaskItem] {
        var alreadyListed = Set(
            existingHourTasks
                .filter { $0.deletedAt == nil && !$0.completed }
                .compactMap { $0.habitId }
        )
        // A server without habit_id can return an older generated hour task
        // unlinked. Its deterministic ID still identifies the owning habit.
        for task in existingHourTasks where task.deletedAt == nil && !task.completed && task.habitId == nil {
            for habit in habits where hourTaskId(habitId: habit.id, now: task.createdAt) == task.id {
                alreadyListed.insert(habit.id)
            }
        }
        let existingIds = Set(existingHourTasks.map(\.id))
        
        var order = startingOrder
        var created: [TaskItem] = []
        var seenInputIds = Set<String>()
        for habit in habits where seenInputIds.insert(habit.id).inserted && !alreadyListed.contains(habit.id) {
            let taskId = hourTaskId(habitId: habit.id, now: now)
            guard !existingIds.contains(taskId) else { continue }
            let text = habit.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let task = TaskItem(text: text, intervalType: hourInterval, order: order, habitId: habit.id)
            task.id = taskId
            task.createdAt = now
            task.updatedAt = now
            created.append(task)
            alreadyListed.insert(habit.id)
            order += 1
        }
        return created
    }

    /// Older server schemas omit habit_id. The generated UUID still lets us
    /// restore the link after a fresh login without guessing from task text.
    @discardableResult
    static func recoverGeneratedLinks(tasks: [TaskItem], habits: [HabitItem]) -> Bool {
        let candidates = tasks.filter { $0.habitId == nil && $0.intervalType == hourInterval }
        guard !candidates.isEmpty else { return false }
        var changed = false
        for task in candidates {
            if let habit = habits.first(where: { hourTaskId(habitId: $0.id, now: task.createdAt) == task.id }) {
                task.habitId = habit.id
                task.syncedAt = nil
                changed = true
            }
        }
        return changed
    }
    
    // MARK: - Completion Mirroring
    
    /// Marks a habit done, or not done, for the current period. Returns whether anything
    /// changed so callers can avoid pointless saves and syncs.
    @discardableResult
    static func setHabitCompleted(_ completed: Bool, on habit: HabitItem, now: Date = Date()) -> Bool {
        if completed {
            guard !habit.isCompleted(at: now) else { return false }
            habit.streak += 1
            habit.lastCompletedDate = now
            habit.setCompletionDates(habit.completionDates + [now])
        } else {
            guard habit.isCompleted(at: now) else { return false }
            habit.streak = max(0, habit.streak - 1)
            habit.lastCompletedDate = nil
            let day = HabitItem.intervalDayDate(for: now)
            let remaining = habit.completionDates.filter {
                !Calendar.current.isDate(HabitItem.intervalDayDate(for: $0), inSameDayAs: day)
            }
            habit.setCompletionDates(remaining)
            // Keep the model's legacy lastCompletedDate field aligned with the
            // newest historical completion when an older completion remains.
            habit.lastCompletedDate = remaining.max()
        }
        habit.updatedAt = now
        return true
    }
    
    @discardableResult
    static func setTaskCompleted(_ completed: Bool, on task: TaskItem, now: Date = Date()) -> Bool {
        guard task.completed != completed else { return false }
        task.completed = completed
        task.completedAt = completed ? now : nil
        task.updatedAt = now
        return true
    }
    
    /// Ticking an hour task ticks the habit it came from.
    @discardableResult
    static func applyTaskCompletionToHabit(_ task: TaskItem, habits: [HabitItem], now: Date = Date()) -> Bool {
        guard let habitId = task.habitId,
              let habit = habits.first(where: { $0.id == habitId && $0.deletedAt == nil }) else { return false }
        return setHabitCompleted(task.completed, on: habit, now: now)
    }
    
    /// Ticking a habit ticks the hour tasks created from it.
    @discardableResult
    static func applyHabitCompletionToTasks(_ habit: HabitItem, tasks: [TaskItem], now: Date = Date()) -> Bool {
        let linked = tasks.filter { $0.habitId == habit.id && $0.deletedAt == nil }
        guard !linked.isEmpty else { return false }
        
        let shouldBeCompleted = habit.isCompleted(at: now)
        var changed = false
        for task in linked {
            if setTaskCompleted(shouldBeCompleted, on: task, now: now) { changed = true }
        }
        return changed
    }

    /// Resolves a sync race between the separately stored habit and linked task rows.
    /// The newest side is authoritative; all linked live tasks are then made consistent.
    @discardableResult
    static func reconcileCompletion(tasks: [TaskItem], habits: [HabitItem]) -> Bool {
        let habitsById = Dictionary(habits.filter { $0.deletedAt == nil }.map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })
        let groupedTasks = Dictionary(grouping: tasks.filter { $0.deletedAt == nil && $0.habitId != nil },
                                      by: { $0.habitId! })
        var changed = false

        for (habitId, linkedTasks) in groupedTasks {
            guard let habit = habitsById[habitId],
                  let newestTask = linkedTasks.max(by: { $0.updatedAt < $1.updatedAt }) else { continue }

            if newestTask.updatedAt > habit.updatedAt {
                if setHabitCompleted(newestTask.completed, on: habit, now: newestTask.updatedAt) { changed = true }
                for task in linkedTasks where task !== newestTask {
                    if setTaskCompleted(newestTask.completed, on: task, now: newestTask.updatedAt) { changed = true }
                }
            } else if habit.updatedAt > newestTask.updatedAt {
                let completed = habit.isCompleted(at: habit.updatedAt)
                for task in linkedTasks {
                    if setTaskCompleted(completed, on: task, now: habit.updatedAt) { changed = true }
                }
            }
        }
        return changed
    }
    
    /// Soft-deletes every live hour task that was created from this habit. Keeps the hour
    /// list from showing a habit that the user has just removed.
    @discardableResult
    static func binLinkedHourTasks(for habit: HabitItem, tasks: [TaskItem], now: Date = Date()) -> [TaskItem] {
        let linked = tasks.filter {
            $0.habitId == habit.id && $0.deletedAt == nil && !$0.completed
        }
        for task in linked {
            task.deletedAt = now
            task.updatedAt = now
        }
        return linked
    }
}
