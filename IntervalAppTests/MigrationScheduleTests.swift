import XCTest

/// Pure calendar progression. No timers, no SwiftData — agents can pin a migration bug here
/// before touching MigrationManager.
final class MigrationScheduleTests: XCTestCase {
    
    private func marker(year: Int? = 2026, month: Int? = 6, week: Int? = 25, day: Int? = 15, hour: Int? = 12) -> CalendarMarker {
        CalendarMarker(hour: hour, day: day, week: week, month: month, year: year)
    }
    
    func testMarkerReadsCalendarComponents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2026-06-15 12:00:00 UTC is a Monday in week 25.
        let date = Date(timeIntervalSince1970: 1_781_524_800)
        let m = MigrationSchedule.marker(for: date, calendar: calendar)
        XCTAssertEqual(m.year, 2026)
        XCTAssertEqual(m.month, 6)
        XCTAssertEqual(m.day, 15)
        XCTAssertEqual(m.hour, 12)
        XCTAssertEqual(m.week, 25)
    }
    
    func testLargestRolloverWinsWhenSeveralIntervalsPass() {
        let previous = marker(year: 2025, month: 12, week: 52, day: 31, hour: 23)
        let current = marker(year: 2026, month: 1, week: 1, day: 1, hour: 0)
        let due = MigrationSchedule.dueMigration(previous: previous, current: current)
        XCTAssertEqual(due?.source, "1 Year")
        XCTAssertEqual(due?.dest, "1 Year")
    }
    
    func testHourRolloverProducesDayToHourMigration() {
        let due = MigrationSchedule.dueMigration(
            previous: marker(hour: 11),
            current: marker(hour: 12),
            isFirstHourAfterDay: true
        )
        XCTAssertEqual(due?.source, "1 Day")
        XCTAssertEqual(due?.dest, HabitTaskLink.hourInterval)
        XCTAssertEqual(due?.isFirstHourOfDay, true)
    }
    
    func testDayRolloverProducesWeekToDayMigration() {
        let due = MigrationSchedule.dueMigration(
            previous: marker(day: 14, hour: 23),
            current: marker(day: 15, hour: 0)
        )
        XCTAssertEqual(due?.source, "1 Week")
        XCTAssertEqual(due?.dest, "1 Day")
    }
    
    func testMissingPreviousValueMeansNothingIsDue() {
        let previous = CalendarMarker(hour: nil, day: nil, week: nil, month: nil, year: nil)
        let due = MigrationSchedule.dueMigration(previous: previous, current: marker())
        XCTAssertNil(due, "First launch must not interrupt the user")
    }
    
    func testNoChangeMeansNothingIsDue() {
        let m = marker()
        XCTAssertNil(MigrationSchedule.dueMigration(previous: m, current: m))
    }
    
    // MARK: - Presentation
    
    func testYearMigrationAlwaysPresents() {
        let migration = Migration(source: "1 Year", dest: "1 Year")
        XCTAssertTrue(MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 0))
    }
    
    func testHourMigrationPresentsWhenOnlyHabitsRemain() {
        let migration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        XCTAssertTrue(MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 2))
        XCTAssertFalse(MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 0))
    }
    
    func testNonHourMigrationRequiresSourceTasks() {
        let migration = Migration(source: "1 Week", dest: "1 Day")
        XCTAssertFalse(MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 5))
        XCTAssertTrue(MigrationSchedule.shouldPresent(migration, sourceTaskCount: 1, selectableHabitCount: 0))
    }
}
