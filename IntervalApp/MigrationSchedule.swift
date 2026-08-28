import Foundation

/// Decides if the migration modal should be presented to the user.
enum MigrationSchedule {
    /// - 1 Year -> 1 Year: Always presents to write new annual goals.
    /// - 1 Day -> 1 Hour: Presents if there is at least one task in the "1 Day" list OR at least one open habit for today OR lingering 1-Hour tasks.
    /// - Day / Week / Month transitions: Present if source list has tasks OR lingering reverse tasks exist.
    static func shouldPresent(_ migration: Migration, sourceTaskCount: Int, selectableHabitCount: Int, reverseTaskCount: Int = 0) -> Bool {
        if migration.source == "1 Year" && migration.dest == "1 Year" {
            return true
        }
        if migration.dest == HabitTaskLink.hourInterval {
            return sourceTaskCount > 0 || selectableHabitCount > 0 || reverseTaskCount > 0
        }
        return sourceTaskCount > 0 || reverseTaskCount > 0
    }
}
