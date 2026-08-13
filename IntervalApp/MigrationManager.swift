import Foundation
import SwiftData
import SwiftUI
import Combine

struct Migration: Identifiable {
    let id = UUID()
    let source: String
    let dest: String
    var isFirstHourOfDay: Bool = false
}

@MainActor
class MigrationManager: ObservableObject {
    @Published var currentMigration: Migration? = nil
    
    private enum StoreKey {
        static let hour = "lastHour"
        static let day = "lastDay"
        static let week = "lastWeek"
        static let month = "lastMonth"
        static let year = "lastYear"
    }
    
    private var timerCancellable: AnyCancellable?
    private var hourTimerCancellable: AnyCancellable?
    private var isFirstHourAfterDayMigration = false
    private var modelContext: ModelContext?
    
    /// Reads live data from the context on every check. Capturing an array here would freeze
    /// the task list at start-up and make the "nothing to migrate" decisions go stale.
    func startMonitoring(context: ModelContext) {
        self.modelContext = context
        timerCancellable?.cancel()
        hourTimerCancellable?.cancel()
        
        // Initial check on launch
        checkMigrations()
        
        // 1. Regular 15-second check (catches wake from sleep / background)
        timerCancellable = Timer.publish(every: 15.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkMigrations()
            }
        
        // 2. Precise top-of-the-hour timer (triggers exactly at :00:00)
        scheduleNextHourTimer()
    }
    
    private func scheduleNextHourTimer() {
        let now = Date()
        let cal = Calendar.current
        guard let nextHour = cal.nextDate(after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) else { return }
        
        let interval = nextHour.timeIntervalSince(now)
        
        hourTimerCancellable = Just(())
            .delay(for: .seconds(interval), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.checkMigrations()
                self.scheduleNextHourTimer()
            }
    }
    
    func checkMigrations() {
        guard currentMigration == nil else { return }
        
        let defaults = UserDefaults.standard
        let now = Date()
        let cal = Calendar.current
        
        // Initial setup for a fresh installation: record current dates without showing modals.
        if defaults.object(forKey: StoreKey.hour) == nil {
            defaults.set(now, forKey: StoreKey.hour)
            defaults.set(now, forKey: StoreKey.day)
            defaults.set(now, forKey: StoreKey.week)
            defaults.set(now, forKey: StoreKey.month)
            defaults.set(now, forKey: StoreKey.year)
            return
        }
        
        let lastHourDate = (defaults.object(forKey: StoreKey.hour) as? Date) ?? now
        let lastDayDate = (defaults.object(forKey: StoreKey.day) as? Date) ?? now
        let lastWeekDate = (defaults.object(forKey: StoreKey.week) as? Date) ?? now
        let lastMonthDate = (defaults.object(forKey: StoreKey.month) as? Date) ?? now
        let lastYearDate = (defaults.object(forKey: StoreKey.year) as? Date) ?? now
        
        var pending: Migration? = nil
        var targetStoreKey: String? = nil
        
        if !cal.isDate(lastYearDate, equalTo: now, toGranularity: .year) {
            pending = Migration(source: "1 Year", dest: "1 Year")
            targetStoreKey = StoreKey.year
        } else if !cal.isDate(lastMonthDate, equalTo: now, toGranularity: .month) {
            pending = Migration(source: "1 Year", dest: "1 Month")
            targetStoreKey = StoreKey.month
        } else if !cal.isDate(lastWeekDate, equalTo: now, toGranularity: .weekOfYear) {
            pending = Migration(source: "1 Month", dest: "1 Week")
            targetStoreKey = StoreKey.week
        } else if !cal.isDate(lastDayDate, equalTo: now, toGranularity: .day) {
            pending = Migration(source: "1 Week", dest: "1 Day")
            targetStoreKey = StoreKey.day
        } else if !cal.isDate(lastHourDate, equalTo: now, toGranularity: .hour) {
            pending = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval, isFirstHourOfDay: isFirstHourAfterDayMigration)
            targetStoreKey = StoreKey.hour
        }
        
        guard let migration = pending, let key = targetStoreKey else { return }
        
        if migration.source == "1 Week" && migration.dest == "1 Day" {
            isFirstHourAfterDayMigration = true
        }
        
        // Update state marker once evaluated
        defaults.set(now, forKey: key)
        
        if present(migration) { return }
        
        // A day migration with nothing to show still hands over to the first hour of the day.
        if migration.source == "1 Week" && migration.dest == "1 Day" {
            presentFirstHourOfDay()
        }
    }
    
    /// Shows the migration when it has something to offer. Returns whether it was shown.
    @discardableResult
    private func present(_ migration: Migration) -> Bool {
        let tasks = activeTasks()
        let sourceCount = tasks.filter { $0.intervalType == migration.source }.count
        // Habits are only offered by the hourly step, so only that step needs to count them.
        let habitCount = migration.dest == HabitTaskLink.hourInterval ? selectableHabits(tasks: tasks).count : 0
        
        guard MigrationSchedule.shouldPresent(migration,
                                              sourceTaskCount: sourceCount,
                                              selectableHabitCount: habitCount) else { return false }
        
        currentMigration = migration
        // The "first hour of the day" wording applies to one migration only.
        if migration.dest == HabitTaskLink.hourInterval {
            isFirstHourAfterDayMigration = false
        }
        return true
    }
    
    private func presentFirstHourOfDay() {
        present(Migration(source: "1 Day", dest: HabitTaskLink.hourInterval, isFirstHourOfDay: true))
    }
    
    func executeMigration(migration: Migration,
                          selectedTaskIds: Set<String>,
                          selectedHabitIds: Set<String> = []) {
        guard let context = modelContext else {
            currentMigration = nil
            return
        }
        
        let allTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let allHabits = (try? context.fetch(FetchDescriptor<HabitItem>())) ?? []
        let active = allTasks.filter { !$0.completed && $0.deletedAt == nil }
        
        var maxOrder = (active.filter { $0.intervalType == migration.dest }.map { $0.order }.max() ?? -1) + 1
        let now = Date()
        
        var droppedTasks: [TaskItem] = []
        for task in active where task.intervalType == migration.source {
            if selectedTaskIds.contains(task.id) {
                task.intervalType = migration.dest
                task.order = maxOrder
                task.updatedAt = now
                maxOrder += 1
            } else if migration.source == migration.dest {
                droppedTasks.append(task)
            }
        }
        
        // Habits picked in the hourly step become hour tasks that stay tied to the habit.
        if !selectedHabitIds.isEmpty {
            let chosen = allHabits.filter { selectedHabitIds.contains($0.id) }
            let created = HabitTaskLink.makeHourTasks(
                for: chosen,
                existingHourTasks: allTasks.filter { $0.intervalType == migration.dest },
                startingOrder: maxOrder,
                now: now
            )
            for task in created {
                context.insert(task)
                maxOrder += 1
            }
        }
        
        // Register the remote delete before removing the rows locally so that a pull already
        // in flight cannot re-create them.
        if !droppedTasks.isEmpty {
            SupabaseSyncManager.shared.deleteRemote(table: SyncTable.tasks, ids: droppedTasks.map { $0.id })
            for task in droppedTasks {
                context.delete(task)
            }
        }
        
        try? context.save()
        SupabaseSyncManager.shared.push()
        currentMigration = nil
        
        // Once the day is planned, move straight on to the first hour of that day.
        if migration.source == "1 Week" && migration.dest == "1 Day" {
            presentFirstHourOfDay()
        }
    }
    
    func triggerSimulatedMigration(source: String, dest: String) {
        currentMigration = Migration(source: source, dest: dest)
    }
    
    func skipMigration() {
        let skipped = currentMigration
        currentMigration = nil
        
        if let skipped, skipped.source == "1 Week" && skipped.dest == "1 Day" {
            presentFirstHourOfDay()
        }
    }
    
    #if DEBUG
    /// Test seam: gives the manager a store without starting any timers.
    func attachForTesting(context: ModelContext) {
        modelContext = context
    }
    
    func presentForTesting(_ migration: Migration) -> Bool {
        present(migration)
    }
    #endif
    
    // MARK: - Live Data
    
    private func activeTasks() -> [TaskItem] {
        guard let context = modelContext else { return [] }
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        return all.filter { !$0.completed && $0.deletedAt == nil }
    }
    
    private func selectableHabits(tasks: [TaskItem]) -> [HabitItem] {
        guard let context = modelContext else { return [] }
        let habits = (try? context.fetch(FetchDescriptor<HabitItem>())) ?? []
        return HabitTaskLink.selectableHabits(
            from: habits,
            hourTasks: tasks.filter { $0.intervalType == HabitTaskLink.hourInterval }
        )
    }
}
