import Foundation

/// Rules connecting habits to the hour tasks created from them during an hourly migration.
/// Ticking either side ticks the other, and streaks are counted exactly once per period.
enum HabitTaskLink {
    static let hourInterval = "1 Hour"
    
    // MARK: - Selection
    
    /// Habits that can still be pulled into the coming hour: not deleted, not already done
    /// for the current period, and not already sitting in the hour list.
    static func selectableHabits(from habits: [HabitItem], hourTasks: [TaskItem], now: Date = Date()) -> [HabitItem] {
        let alreadyListed = Set(
            hourTasks
                .filter { $0.deletedAt == nil && !$0.completed }
                .compactMap { $0.habitId }
        )
        return habits
            .filter { $0.deletedAt == nil }
            .filter { $0.isScheduledForTodayOrOverdue(date: now) }
            .filter { !$0.isCompleted(at: now) }
            .filter { !alreadyListed.contains($0.id) }
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
        let alreadyListed = Set(
            existingHourTasks
                .filter { $0.deletedAt == nil && !$0.completed }
                .compactMap { $0.habitId }
        )
        
        var order = startingOrder
        var created: [TaskItem] = []
        for habit in habits where !alreadyListed.contains(habit.id) {
            let text = habit.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let task = TaskItem(text: text, intervalType: hourInterval, order: order, habitId: habit.id)
            task.updatedAt = now
            created.append(task)
            order += 1
        }
        return created
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
        } else {
            guard habit.isCompleted(at: now) else { return false }
            habit.streak = max(0, habit.streak - 1)
            habit.lastCompletedDate = nil
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
