import XCTest
import SwiftData

/// Validates habit period calculations, custom dayStartHour boundaries, weekly scheduling, and streak increments.
@MainActor
final class HabitPeriodicResetAndStreakTests: XCTestCase {
    private var store: TestStore!
    private let now = TestTime.now // Monday 2026-06-15 12:00:00 UTC
    
    override func setUp() async throws {
        try await super.setUp()
        store = try TestStore()
    }
    
    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }
    
    // MARK: - Interval Day Date Offset (Default 06:00 AM Threshold)
    
    func testIntervalDayDateAppliesConfiguredHourOffset() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        
        // 2026-06-15 05:00 UTC (before 6 AM threshold) belongs to the PREVIOUS interval day (2026-06-14)
        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 5, minute: 0))!
        let intervalDateEarly = HabitItem.intervalDayDate(for: earlyMorning, calendar: calendar)
        let dayComponentEarly = calendar.component(.day, from: intervalDateEarly)
        XCTAssertEqual(dayComponentEarly, 14, "5:00 AM belongs to previous interval day (before 6 AM)")
        
        // 2026-06-15 07:00 UTC (after 6 AM threshold) belongs to the CURRENT interval day (2026-06-15)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 7, minute: 0))!
        let intervalDateMorning = HabitItem.intervalDayDate(for: morning, calendar: calendar)
        let dayComponentMorning = calendar.component(.day, from: intervalDateMorning)
        XCTAssertEqual(dayComponentMorning, 15, "7:00 AM belongs to current interval day")
    }
    
    // MARK: - Weekly Habit Target Weekday & Overdue Calculation
    
    func testWeeklyHabitOverdueWhenTargetDayPassedInCurrentWeek() {
        // Monday 2026-06-15 (weekday 2 in ISO / Gregorian)
        // If weekly habit was due on Sunday (weekday 1) or past weekday in current week
        let weeklyHabit = store.addHabit("Clean Desk", frequency: "Weekly:2", order: 0) // Due Monday
        XCTAssertTrue(weeklyHabit.isScheduledForToday(date: now))
        XCTAssertFalse(weeklyHabit.isOverdueInCurrentWeek(date: now))
    }

    func testMultiDayWeeklyHabitCreatesACompletionPeriodForEachSelectedDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let habit = store.addHabit("Run", frequency: "Weekly:2,4", order: 0)
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 12))!
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 12))!

        XCTAssertTrue(habit.isScheduled(on: now, calendar: calendar))
        XCTAssertFalse(habit.isScheduled(on: tuesday, calendar: calendar))
        XCTAssertTrue(habit.isScheduledForTodayOrOverdue(calendar: calendar, date: tuesday))
        habit.lastCompletedDate = now
        XCTAssertFalse(habit.isScheduledForTodayOrOverdue(calendar: calendar, date: tuesday))
        XCTAssertTrue(habit.isScheduled(on: wednesday, calendar: calendar))
        XCTAssertFalse(habit.isCompleted(at: wednesday, calendar: calendar))
    }

    func testMonthlyHabitUsesSelectedDayAndClampsToShortMonths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let habit = store.addHabit("Pay rent", frequency: "Monthly:31", order: 0)
        let february28 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 12))!
        let march30 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 12))!
        let march31 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 12))!

        XCTAssertTrue(habit.isScheduled(on: february28, calendar: calendar))
        habit.lastCompletedDate = february28
        XCTAssertTrue(habit.isCompleted(at: march30, calendar: calendar))
        XCTAssertTrue(habit.isScheduled(on: march31, calendar: calendar))
        XCTAssertFalse(habit.isCompleted(at: march31, calendar: calendar))
    }

    func testMonthlyHabitCanRepeatOnSeveralDatesInEachMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let habit = store.addHabit("Water plants", frequency: "Monthly:1,15,31", order: 0)
        let february15 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15, hour: 12))!
        let february28 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 12))!

        XCTAssertTrue(habit.isScheduled(on: february15, calendar: calendar))
        XCTAssertTrue(habit.isScheduled(on: february28, calendar: calendar), "The 31st falls on February's last day")
        XCTAssertFalse(habit.isScheduled(on: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 12))!, calendar: calendar))
    }

    func testBiweeklyHabitUsesSelectedDaysOnlyOnAnchoredWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        let frequency = "Weekly:2,4;interval=2;anchor=\(anchor.timeIntervalSince1970)"
        let habit = store.addHabit("Training", frequency: frequency, order: 0)
        let june17 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 12))!
        let june22 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 12))!
        let june29 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!

        XCTAssertTrue(habit.isScheduled(on: anchor, calendar: calendar))
        XCTAssertTrue(habit.isScheduled(on: june17, calendar: calendar))
        XCTAssertFalse(habit.isScheduled(on: june22, calendar: calendar))
        XCTAssertTrue(habit.isScheduled(on: june29, calendar: calendar))
        XCTAssertEqual(habit.weeklyInterval, 2)
    }
    
    // MARK: - Streak Preservation and Single-Increment Rule
    
    func testTickingHabitMultipleTimesDoesNotMultiplyStreak() throws {
        let habit = store.addHabit("Meditate", frequency: "Daily", streak: 5, id: "h1")
        
        // First completion for today
        HabitTaskLink.setHabitCompleted(true, on: habit, now: now)
        XCTAssertEqual(habit.streak, 6)
        XCTAssertEqual(habit.lastCompletedDate, now)
        
        // Second completion call on same day (idempotent)
        let didChange = HabitTaskLink.setHabitCompleted(true, on: habit, now: now)
        XCTAssertFalse(didChange, "Subsequent complete call on same period must be a no-op")
        XCTAssertEqual(habit.streak, 6, "Streak must remain 6")
    }
    
    // MARK: - Postpone Expires on Next Interval Day
    
    func testPostponeIsActiveTodayAndInactiveNextDay() {
        let habit = store.addHabit("Gym Session", frequency: "Daily", postponedDate: now, id: "h-gym")
        
        // Active on the same day
        XCTAssertTrue(habit.isPostponed(at: now))
        
        // Next day (24 hours later)
        let nextDay = now.addingTimeInterval(86400)
        XCTAssertFalse(habit.isPostponed(at: nextDay), "Postpone for today must expire on the next day")
    }
}
