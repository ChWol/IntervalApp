import Foundation
import SwiftData

@Model
final class HabitItem {
    var id: String = UUID().uuidString
    var text: String = ""
    var frequency: String = "Daily"
    var streak: Int = 0
    var lastCompletedDate: Date? = nil
    var order: Int = 0
    var deletedAt: Date? = nil
    var updatedAt: Date = Date()
    /// Value of `updatedAt` at the time the row was last confirmed by the server.
    /// `nil`, or older than `updatedAt`, means the row still has unpublished local changes.
    var syncedAt: Date? = nil
    
    init(text: String, frequency: String = "Daily", order: Int = 0) {
        self.id = UUID().uuidString
        self.text = text
        self.frequency = frequency
        self.streak = 0
        self.order = order
        self.deletedAt = nil
        self.updatedAt = Date()
        self.syncedAt = nil
    }
    
    var isDaily: Bool {
        frequency.lowercased().starts(with: "daily")
    }
    
    var isWeekly: Bool {
        frequency.lowercased().starts(with: "weekly")
    }
    
    /// Target weekday for weekly habits: 1 = Sun, 2 = Mon, 3 = Tue, 4 = Wed, 5 = Thu, 6 = Fri, 7 = Sat (Calendar.component(.weekday))
    var targetWeekday: Int? {
        get {
            guard isWeekly else { return nil }
            let parts = frequency.split(separator: ":")
            if parts.count > 1, let day = Int(parts[1]) {
                return day
            }
            if parts.count > 1 {
                let name = String(parts[1]).lowercased()
                switch name {
                case "sunday", "sun", "so", "sonntag": return 1
                case "monday", "mon", "mo", "montag": return 2
                case "tuesday", "tue", "di", "dienstag": return 3
                case "wednesday", "wed", "mi", "mittwoch": return 4
                case "thursday", "thu", "do", "donnerstag": return 5
                case "friday", "fri", "fr", "freitag": return 6
                case "saturday", "sat", "sa", "samstag": return 7
                default: return nil
                }
            }
            return nil
        }
        set {
            if let day = newValue {
                frequency = "Weekly:\(day)"
            } else {
                frequency = "Weekly"
            }
        }
    }
    
    var isCompletedCurrentPeriod: Bool {
        isCompleted(at: Date())
    }
    
    /// Returns the start of the day for the most recent occurrence of `targetWeekday` on or before `date`.
    static func mostRecentWeekdayDate(targetWeekday: Int, beforeOrOn date: Date, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        let currentWeekday = calendar.component(.weekday, from: startOfToday)
        let daysAgo = (currentWeekday - targetWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday) ?? startOfToday
    }
    
    /// Returns true if this weekly habit is currently overdue (i.e. not yet completed in the rolling 7-day cycle since its scheduled weekday, and today is not that scheduled weekday).
    func isOverdue(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isWeekly, let target = targetWeekday else { return false }
        guard !isCompleted(at: date, calendar: calendar) else { return false }
        let currentWeekday = calendar.component(.weekday, from: date)
        // If today is the target weekday itself, it is today's normal habit, not overdue.
        // If today is after the target weekday in the 7-day cycle and still incomplete, it is overdue.
        return currentWeekday != target
    }
    
    /// Backward-compatible alias
    func isOverdueInCurrentWeek(calendar: Calendar = .current, date: Date = Date()) -> Bool {
        isOverdue(at: date, calendar: calendar)
    }
    
    /// Whether this habit should be shown in the habits bar today (either scheduled for today, or overdue from its rolling cycle).
    func isScheduledForTodayOrOverdue(calendar: Calendar = .current, date: Date = Date()) -> Bool {
        if isDaily { return true }
        guard let target = targetWeekday else { return true }
        let currentWeekday = calendar.component(.weekday, from: date)
        
        if isCompleted(at: date, calendar: calendar) {
            // Once completed for this 7-day period, only show on its regular target day
            return currentWeekday == target
        }
        
        // If incomplete: visible on its scheduled day AND every following day until next occurrence!
        return true
    }
    
    /// Backward-compatible alias
    func isScheduledForToday(calendar: Calendar = .current, date: Date = Date()) -> Bool {
        isScheduledForTodayOrOverdue(calendar: calendar, date: date)
    }
    
    /// Whether the habit counts as done for the period containing `date`.
    /// For weekly habits, checks if `lastCompletedDate` occurred on or after the most recent occurrence of `targetWeekday`.
    func isCompleted(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let last = lastCompletedDate else { return false }
        if isDaily {
            return calendar.isDate(last, inSameDayAs: date)
        }
        if let target = targetWeekday {
            let cycleStart = Self.mostRecentWeekdayDate(targetWeekday: target, beforeOrOn: date, calendar: calendar)
            return last >= cycleStart
        }
        return calendar.isDate(last, equalTo: date, toGranularity: .weekOfYear)
    }
}
