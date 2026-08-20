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
                case "sunday", "sun", "so", "sonntag", "dimanche", "dim", "domingo", "dom", "domenica", "周日", "星期日", "日", "日曜日", "일", "일요일", "الأحد", "أحد", "اح": return 1
                case "monday", "mon", "mo", "montag", "lundi", "lun", "lunes", "segunda", "segunda-feira", "seg", "lunedì", "lunedi", "周一", "星期一", "月", "月曜日", "월", "월요일", "الإثنين", "إثنين", "اثنين", "اث": return 2
                case "tuesday", "tue", "di", "dienstag", "mardi", "mar", "martes", "terça", "terca", "terça-feira", "ter", "martedì", "martedi", "周二", "星期二", "火", "火曜日", "화", "화요일", "الثلاثاء", "ثلاثاء", "ثل": return 3
                case "wednesday", "wed", "mi", "mittwoch", "mercredi", "mer", "miércoles", "miercoles", "quarta", "quarta-feira", "qua", "mie", "mercoledì", "mercoledi", "周三", "星期三", "水", "水曜日", "수", "수요일", "الأربعاء", "أربعاء", "اربعاء", "ار": return 4
                case "thursday", "thu", "do", "donnerstag", "jeudi", "jeu", "jueves", "quinta", "quinta-feira", "qui", "jue", "giovedì", "giovedi", "gio", "周四", "星期四", "木", "木曜日", "목", "목요일", "الخميس", "خميس", "خم": return 5
                case "friday", "fri", "fr", "freitag", "vendredi", "ven", "viernes", "sexta", "sexta-feira", "sex", "vie", "venerdì", "venerdi", "周五", "星期五", "金", "金曜日", "금", "금요일", "الجمعة", "جمعة", "جم": return 6
                case "saturday", "sat", "sa", "samstag", "samedi", "sam", "sábado", "sabado", "sab", "sabato", "周六", "星期六", "土", "土曜日", "토", "토요일", "السبت", "سبت", "سب": return 7
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
    
    /// Adjusts any timestamp according to the configured dayStartHour and dayStartMinute (default 06:00).
    /// A date before the day start threshold belongs to the previous interval day.
    static func intervalDayDate(for date: Date = Date(), calendar: Calendar = .current) -> Date {
        let hour = UserDefaults.standard.object(forKey: "dayStartHour") != nil ? UserDefaults.standard.integer(forKey: "dayStartHour") : 6
        let minute = UserDefaults.standard.integer(forKey: "dayStartMinute")
        let offsetSeconds = Double(hour * 3600 + minute * 60)
        return date.addingTimeInterval(-offsetSeconds)
    }
    
    /// Returns the start of the day for the most recent occurrence of `targetWeekday` on or before `date`.
    static func mostRecentWeekdayDate(targetWeekday: Int, beforeOrOn date: Date, calendar: Calendar = .current) -> Date {
        let adjusted = intervalDayDate(for: date, calendar: calendar)
        let startOfToday = calendar.startOfDay(for: adjusted)
        let currentWeekday = calendar.component(.weekday, from: startOfToday)
        let daysAgo = (currentWeekday - targetWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday) ?? startOfToday
    }
    
    /// Returns true if this weekly habit is currently overdue (i.e. not yet completed in the rolling 7-day cycle since its scheduled weekday, and today is not that scheduled weekday).
    func isOverdue(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isWeekly, let target = targetWeekday else { return false }
        guard !isCompleted(at: date, calendar: calendar) else { return false }
        let adjusted = Self.intervalDayDate(for: date, calendar: calendar)
        let currentWeekday = calendar.component(.weekday, from: adjusted)
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
        let adjusted = Self.intervalDayDate(for: date, calendar: calendar)
        let currentWeekday = calendar.component(.weekday, from: adjusted)
        
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
        let adjustedNow = Self.intervalDayDate(for: date, calendar: calendar)
        let adjustedLast = Self.intervalDayDate(for: last, calendar: calendar)
        
        if isDaily {
            return calendar.isDate(adjustedLast, inSameDayAs: adjustedNow)
        }
        if let target = targetWeekday {
            let cycleStart = Self.mostRecentWeekdayDate(targetWeekday: target, beforeOrOn: date, calendar: calendar)
            let startOfLast = calendar.startOfDay(for: adjustedLast)
            return startOfLast >= cycleStart
        }
        return calendar.isDate(adjustedLast, equalTo: adjustedNow, toGranularity: .weekOfYear)
    }
}
