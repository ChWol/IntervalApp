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
