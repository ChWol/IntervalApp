import XCTest

/// Validates presentation criteria for transitions across all interval levels.
final class MigrationScheduleTests: XCTestCase {
    
    func testYearResetAlwaysPresentsEvenWithZeroTasks() {
        let migration = Migration(source: "1 Year", dest: "1 Year")
        XCTAssertTrue(
            MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 0),
            "Annual reset should always present so the user can set new yearly goals"
        )
    }
    
    func testHourMigrationPresentsWhenDayTasksExist() {
        let migration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        XCTAssertTrue(
            MigrationSchedule.shouldPresent(migration, sourceTaskCount: 3, selectableHabitCount: 0)
        )
    }
    
    func testHourMigrationPresentsWhenOnlyHabitsExist() {
        let migration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        XCTAssertTrue(
            MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 2)
        )
    }
    
    func testHourMigrationDoesNotPresentWhenBothTasksAndHabitsAreEmpty() {
        let migration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval)
        XCTAssertFalse(
            MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 0)
        )
    }
    
    func testDayMigrationPresentsOnlyWhenWeekTasksExist() {
        let migration = Migration(source: "1 Week", dest: "1 Day")
        XCTAssertTrue(
            MigrationSchedule.shouldPresent(migration, sourceTaskCount: 1, selectableHabitCount: 0)
        )
        XCTAssertFalse(
            MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 5),
            "Day migration depends strictly on week tasks, not habits"
        )
    }
    
    func testWeekMigrationPresentsOnlyWhenMonthTasksExist() {
        let migration = Migration(source: "1 Month", dest: "1 Week")
        XCTAssertTrue(
            MigrationSchedule.shouldPresent(migration, sourceTaskCount: 2, selectableHabitCount: 0)
        )
        XCTAssertFalse(
            MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 0)
        )
    }
    
    func testMonthMigrationPresentsOnlyWhenYearTasksExist() {
        let migration = Migration(source: "1 Year", dest: "1 Month")
        XCTAssertTrue(
            MigrationSchedule.shouldPresent(migration, sourceTaskCount: 1, selectableHabitCount: 0)
        )
        XCTAssertFalse(
            MigrationSchedule.shouldPresent(migration, sourceTaskCount: 0, selectableHabitCount: 0)
        )
    }
}
