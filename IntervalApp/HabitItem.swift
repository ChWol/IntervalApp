import Foundation
import SwiftData

@Model
final class HabitItem {
    var id: String = UUID().uuidString
    var text: String = ""
    var frequency: String = "Daily"
    var streak: Int = 0
    var lastCompletedDate: Date? = nil
    /// Day-level completion history used for the habit statistics view. Kept as
    /// JSON so older SwiftData stores can migrate without a destructive schema change.
    var completionHistoryJSON: String = "[]"
    var order: Int = 0
    var deletedAt: Date? = nil
    var updatedAt: Date = Date()
    /// Value of `updatedAt` at the time the row was last confirmed by the server.
    /// `nil`, or older than `updatedAt`, means the row still has unpublished local changes.
    var syncedAt: Date? = nil
    var postponedDate: Date? = nil
    
    init(text: String, frequency: String = "Daily", order: Int = 0) {
        self.id = UUID().uuidString
        self.text = text
        self.frequency = frequency
        self.streak = 0
        self.completionHistoryJSON = "[]"
        self.order = order
        self.deletedAt = nil
        self.updatedAt = Date()
        self.syncedAt = nil
        self.postponedDate = nil
    }

    var completionDates: [Date] {
        guard let data = completionHistoryJSON.data(using: .utf8),
              let dates = try? JSONDecoder().decode([Date].self, from: data) else { return [] }
        return dates
    }

    func setCompletionDates(_ dates: [Date]) {
        var byDay: [Date: Date] = [:]
        let calendar = Calendar.current
        for date in dates {
            let dayKey = calendar.startOfDay(for: Self.intervalDayDate(for: date))
            byDay[dayKey] = date
        }
        let unique = byDay.values.sorted()
        guard let data = try? JSONEncoder().encode(unique),
              let json = String(data: data, encoding: .utf8) else { return }
        completionHistoryJSON = json
    }

    /// Consecutive completed scheduled periods ending in this or the preceding period.
    func currentStreak(at date: Date = Date(), calendar: Calendar = .current) -> Int {
        let history = completionDates + (lastCompletedDate.map { [$0] } ?? [])
        let days = Set(history.filter { $0 <= date }.map {
            calendar.startOfDay(for: Self.intervalDayDate(for: $0, calendar: calendar))
        })
        guard !days.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: Self.intervalDayDate(for: date, calendar: calendar))
        if !isDaily, let cycle = mostRecentScheduledDate(onOrBefore: date, calendar: calendar) {
            var count = 0
            var start = cycle
            if !days.contains(where: { $0 >= start && $0 <= today }) {
                guard let previous = previousScheduledDate(before: start, calendar: calendar) else { return 0 }
                start = previous
            }
            while days.contains(where: { $0 >= start && $0 < (nextScheduledDate(after: start, calendar: calendar) ?? start) }) {
                count += 1
                guard let previous = previousScheduledDate(before: start, calendar: calendar) else { break }
                start = previous
            }
            return count
        }
        var day = today
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
    
    /// Whether the habit is currently postponed/snoozed for a given date.
    func isPostponed(at date: Date = Date()) -> Bool {
        guard let postponed = postponedDate else { return false }
        let calendar = Calendar.current
        let adjustedNow = Self.intervalDayDate(for: date, calendar: calendar)
        let adjustedPostponed = Self.intervalDayDate(for: postponed, calendar: calendar)
        return calendar.isDate(adjustedPostponed, inSameDayAs: adjustedNow)
    }
    
    var isPostponedToday: Bool {
        isPostponed(at: Date())
    }
    
    func togglePostponeForToday() {
        if isPostponedToday {
            postponedDate = nil
        } else {
            postponedDate = Date()
        }
        updatedAt = Date()
    }
    
    var isDaily: Bool {
        frequency.lowercased().starts(with: "daily")
    }
    
    var isWeekly: Bool {
        frequency.lowercased().starts(with: "weekly")
    }

    var isMonthly: Bool {
        frequency.lowercased().starts(with: "monthly")
    }

    var targetWeekdays: Set<Int> {
        guard isWeekly else { return [] }
        let raw = frequency.split(separator: ":", maxSplits: 1).last.map(String.init)?.components(separatedBy: ";").first ?? ""
        let values = raw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) }
        if !values.isEmpty { return Set(values) }
        if let day = targetWeekday { return [day] }
        return []
    }

    var targetMonthDays: Set<Int> {
        guard isMonthly,
              let raw = frequency.split(separator: ":", maxSplits: 1).last.map(String.init)?.components(separatedBy: ";").first else { return [] }
        return Set(raw.split(separator: ",").compactMap { Int($0) }.filter { (1...31).contains($0) })
    }

    var targetMonthDay: Int? {
        targetMonthDays.sorted().first
    }

    var weeklyInterval: Int {
        guard isWeekly,
              let value = frequency.components(separatedBy: "interval=").dropFirst().first?.split(separator: ";").first,
              let interval = Int(value) else { return 1 }
        return min(max(interval, 1), 52)
    }

    private var weeklyAnchorDate: Date? {
        guard let raw = frequency.components(separatedBy: "anchor=").dropFirst().first?.split(separator: ";").first,
              let timestamp = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Target weekday for weekly habits: 1 = Sun, 2 = Mon, 3 = Tue, 4 = Wed, 5 = Thu, 6 = Fri, 7 = Sat (Calendar.component(.weekday))
    var targetWeekday: Int? {
        get {
            guard isWeekly else { return nil }
            let raw = frequency.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
            let days = raw.components(separatedBy: ";").first?.split(separator: ",") ?? []
            if let day = days.first.flatMap({ Int($0) }) {
                return day
            }
            let parts = frequency.split(separator: ":")
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
            updatedAt = Date()
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
        if isWeekly && targetWeekdays.isEmpty { return false }
        guard !isDaily, let schedule = mostRecentScheduledDate(onOrBefore: date, calendar: calendar) else { return false }
        guard !isCompleted(at: date, calendar: calendar) else { return false }
        let adjusted = Self.intervalDayDate(for: date, calendar: calendar)
        return !calendar.isDate(schedule, inSameDayAs: calendar.startOfDay(for: adjusted))
    }
    
    /// Backward-compatible alias
    func isOverdueInCurrentWeek(calendar: Calendar = .current, date: Date = Date()) -> Bool {
        isOverdue(at: date, calendar: calendar)
    }
    
    /// Whether this habit should be shown in the habits bar today (either scheduled for today, or overdue from its rolling cycle).
    func isScheduledForTodayOrOverdue(calendar: Calendar = .current, date: Date = Date()) -> Bool {
        if isDaily { return true }
        let adjusted = Self.intervalDayDate(for: date, calendar: calendar)
        let scheduledToday = isScheduled(on: date, calendar: calendar)
        
        if isCompleted(at: date, calendar: calendar) {
            // Once completed for this 7-day period, only show on its regular target day
            return scheduledToday
        }
        
        // If incomplete: visible on its scheduled day AND every following day until next occurrence!
        return scheduledToday || isOverdue(at: date, calendar: calendar)
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
        if !isDaily, let cycleStart = mostRecentScheduledDate(onOrBefore: date, calendar: calendar) {
            let startOfLast = calendar.startOfDay(for: adjustedLast)
            return startOfLast >= cycleStart
        }
        return calendar.isDate(adjustedLast, equalTo: adjustedNow, toGranularity: .weekOfYear)
    }

    func isScheduled(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let adjusted = calendar.startOfDay(for: Self.intervalDayDate(for: date, calendar: calendar))
        if isDaily { return true }
        return isScheduled(onIntervalDay: adjusted, calendar: calendar)
    }

    func mostRecentScheduledDate(onOrBefore date: Date, calendar: Calendar = .current) -> Date? {
        let adjusted = calendar.startOfDay(for: Self.intervalDayDate(for: date, calendar: calendar))
        guard !isDaily else { return adjusted }
        if isWeekly && targetWeekdays.isEmpty {
            for offset in 0...400 {
                guard let candidate = calendar.date(byAdding: .day, value: -offset, to: adjusted),
                      let weekStart = calendar.dateInterval(of: .weekOfYear, for: candidate)?.start,
                      isActiveWeeklyWeek(weekStart, calendar: calendar) else { continue }
                return weekStart
            }
            return nil
        }
        for offset in 0...400 {
            guard let candidate = calendar.date(byAdding: .day, value: -offset, to: adjusted) else { continue }
            if isScheduled(onIntervalDay: candidate, calendar: calendar) {
                return calendar.startOfDay(for: candidate)
            }
        }
        return nil
    }

    func previousScheduledDate(before date: Date, calendar: Calendar = .current) -> Date? {
        guard let priorDay = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        return mostRecentScheduledDate(onOrBefore: priorDay, calendar: calendar)
    }

    func nextScheduledDate(after date: Date, calendar: Calendar = .current) -> Date? {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
        if isWeekly && targetWeekdays.isEmpty {
            for offset in 0...400 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: nextDay),
                      let weekStart = calendar.dateInterval(of: .weekOfYear, for: candidate)?.start,
                      weekStart > date, isActiveWeeklyWeek(weekStart, calendar: calendar) else { continue }
                return weekStart
            }
            return nil
        }
        for offset in 0...400 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: nextDay) else { continue }
            if isScheduled(onIntervalDay: candidate, calendar: calendar) {
                return calendar.startOfDay(for: candidate)
            }
        }
        return nil
    }

    private func isScheduled(onIntervalDay day: Date, calendar: Calendar) -> Bool {
        if isDaily { return true }
        if isWeekly {
            guard isActiveWeeklyWeek(day, calendar: calendar) else { return false }
            return targetWeekdays.isEmpty || targetWeekdays.contains(calendar.component(.weekday, from: day))
        }
        if isMonthly, !targetMonthDays.isEmpty {
            let dayOfMonth = calendar.component(.day, from: day)
            let monthLength = calendar.range(of: .day, in: .month, for: day)?.count ?? dayOfMonth
            return targetMonthDays.contains(dayOfMonth) || (dayOfMonth == monthLength && targetMonthDays.contains(where: { $0 > monthLength }))
        }
        return true
    }

    private func isActiveWeeklyWeek(_ date: Date, calendar: Calendar) -> Bool {
        guard weeklyInterval > 1, let anchor = weeklyAnchorDate,
              let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start,
              let candidateWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return true }
        let elapsedDays = calendar.dateComponents([.day], from: anchorWeek, to: candidateWeek).day ?? 0
        let weeks = elapsedDays / 7
        return weeks >= 0 && weeks % weeklyInterval == 0
    }
}
