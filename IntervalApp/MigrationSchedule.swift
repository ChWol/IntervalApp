import Foundation

/// The calendar position of a moment, at the granularities the app migrates on.
struct CalendarMarker: Equatable {
    var hour: Int?
    var day: Int?
    var week: Int?
    var month: Int?
    var year: Int?
    
    var isComplete: Bool {
        hour != nil && day != nil && week != nil && month != nil && year != nil
    }
}

/// Decides which migration is due and whether it is worth interrupting the user for.
/// Pure so the progression can be tested without waiting on timers.
enum MigrationSchedule {
    static func marker(for date: Date, calendar: Calendar = .current) -> CalendarMarker {
        CalendarMarker(
            hour: calendar.component(.hour, from: date),
            day: calendar.component(.day, from: date),
            week: calendar.component(.weekOfYear, from: date),
            month: calendar.component(.month, from: date),
            year: calendar.component(.year, from: date)
        )
    }
    
    /// The largest interval that has rolled over since `previous`. Only one migration is
    /// produced even when several intervals elapsed at once. A missing previous value means
    /// this is the first run for that granularity and nothing is due.
    static func dueMigration(previous: CalendarMarker, current: CalendarMarker, isFirstHourAfterDay: Bool = false) -> Migration? {
        if let year = previous.year, year != current.year {
            return Migration(source: "1 Year", dest: "1 Year")
        }
        if let month = previous.month, month != current.month {
            return Migration(source: "1 Year", dest: "1 Month")
        }
        if let week = previous.week, week != current.week {
            return Migration(source: "1 Month", dest: "1 Week")
        }
        if let day = previous.day, day != current.day {
            return Migration(source: "1 Week", dest: "1 Day")
        }
        if let hour = previous.hour, hour != current.hour {
            return Migration(source: "1 Day", dest: HabitTaskLink.hourInterval, isFirstHourOfDay: isFirstHourAfterDay)
        }
        return nil
    }
    
    /// Whether the modal has anything to offer. The yearly reset always shows, because it is
    /// where new goals get written rather than moved.
    static func shouldPresent(_ migration: Migration, sourceTaskCount: Int, selectableHabitCount: Int) -> Bool {
        if migration.source == "1 Year" { return true }
        // The hourly step also offers habits, so it is worth showing with an empty day list.
        if migration.dest == HabitTaskLink.hourInterval {
            return sourceTaskCount > 0 || selectableHabitCount > 0
        }
        return sourceTaskCount > 0
    }
}
