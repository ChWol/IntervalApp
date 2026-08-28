import Foundation

struct TaskAgingHelper {
    static let hourToDayThreshold: TimeInterval = 3 * 3600          // 3 hours
    static let dayToWeekThreshold: TimeInterval = 2 * 86400         // 2 days
    static let weekToMonthThreshold: TimeInterval = 14 * 86400      // 2 weeks
    static let monthToYearThreshold: TimeInterval = 90 * 86400      // 3 months (90 days)

    /// Returns the reverse parent interval for a given interval if one exists.
    static func parentInterval(for interval: String) -> String? {
        switch interval {
        case HabitTaskLink.hourInterval, "1 Hour":
            return "1 Day"
        case "1 Day":
            return "1 Week"
        case "1 Week":
            return "1 Month"
        case "1 Month":
            return "1 Year"
        default:
            return nil
        }
    }

    /// Threshold required for a task in `interval` to qualify for reverse suggestion.
    static func threshold(for interval: String) -> TimeInterval? {
        switch interval {
        case HabitTaskLink.hourInterval, "1 Hour":
            return hourToDayThreshold
        case "1 Day":
            return dayToWeekThreshold
        case "1 Week":
            return weekToMonthThreshold
        case "1 Month":
            return monthToYearThreshold
        default:
            return nil
        }
    }

    /// Checks if a task has stayed in its current interval longer than the threshold.
    static func isLingering(_ task: TaskItem, at now: Date = Date()) -> Bool {
        guard !task.completed, task.deletedAt == nil else { return false }
        // Habit-linked tasks are daily routines and must never be demoted
        guard task.habitId == nil else { return false }
        guard let th = threshold(for: task.intervalType) else { return false }
        
        let age = now.timeIntervalSince(task.createdAt)
        return age >= th
    }

    /// Finds lingering tasks in the destination interval for a given migration.
    static func findLingeringTasks(for migration: Migration, in allTasks: [TaskItem], at now: Date = Date()) -> [TaskItem] {
        let dest = migration.dest
        guard threshold(for: dest) != nil else { return [] }
        return allTasks
            .filter { $0.intervalType == dest && isLingering($0, at: now) }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
