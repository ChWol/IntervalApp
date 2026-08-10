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
    
    private var timerCancellable: AnyCancellable?
    private var hourTimerCancellable: AnyCancellable?
    private var isFirstHourAfterDayMigration = false
    
    func startMonitoring(allTasks: [TaskItem]) {
        timerCancellable?.cancel()
        hourTimerCancellable?.cancel()
        
        // Initial check on launch
        checkMigrations(allTasks: allTasks)
        
        // 1. Regular 15-second check (catches wake from sleep / background)
        timerCancellable = Timer.publish(every: 15.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.checkMigrations(allTasks: allTasks)
            }
        
        // 2. Precise top-of-the-hour timer (triggers exactly at :00:00)
        scheduleNextHourTimer(allTasks: allTasks)
    }
    
    private func scheduleNextHourTimer(allTasks: [TaskItem]) {
        let now = Date()
        let cal = Calendar.current
        guard let nextHour = cal.nextDate(after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) else { return }
        
        let interval = nextHour.timeIntervalSince(now)
        
        hourTimerCancellable = Just(())
            .delay(for: .seconds(interval), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.checkMigrations(allTasks: allTasks)
                self.scheduleNextHourTimer(allTasks: allTasks)
            }
    }
    
    func checkMigrations(allTasks: [TaskItem]) {
        guard currentMigration == nil else { return }
        
        let defaults = UserDefaults.standard
        let now = Date()
        let cal = Calendar.current
        
        let currentHour = cal.component(.hour, from: now)
        let currentDay = cal.component(.day, from: now)
        let currentMonth = cal.component(.month, from: now)
        let currentYear = cal.component(.year, from: now)
        let currentWeek = cal.component(.weekOfYear, from: now)
        
        let lastHour = defaults.object(forKey: "lastHour") as? Int
        let lastDay = defaults.object(forKey: "lastDay") as? Int
        let lastMonth = defaults.object(forKey: "lastMonth") as? Int
        let lastYear = defaults.object(forKey: "lastYear") as? Int
        let lastWeek = defaults.object(forKey: "lastWeek") as? Int
        
        var pendingMigration: Migration? = nil
        
        // Priority order (only trigger ONCE even if multiple intervals passed)
        if let ly = lastYear, ly != currentYear {
            pendingMigration = Migration(source: "1 Year", dest: "1 Year")
        } else if let lm = lastMonth, lm != currentMonth {
            pendingMigration = Migration(source: "1 Year", dest: "1 Month")
        } else if let lw = lastWeek, lw != currentWeek {
            pendingMigration = Migration(source: "1 Month", dest: "1 Week")
        } else if let ld = lastDay, ld != currentDay {
            pendingMigration = Migration(source: "1 Week", dest: "1 Day")
            isFirstHourAfterDayMigration = true
        } else if let lh = lastHour, lh != currentHour {
            var m = Migration(source: "1 Day", dest: "1 Hour")
            if isFirstHourAfterDayMigration {
                m.isFirstHourOfDay = true
            }
            pendingMigration = m
        }
        
        // Save latest state
        defaults.set(currentHour, forKey: "lastHour")
        defaults.set(currentDay, forKey: "lastDay")
        defaults.set(currentWeek, forKey: "lastWeek")
        defaults.set(currentMonth, forKey: "lastMonth")
        defaults.set(currentYear, forKey: "lastYear")
        
        if let migration = pendingMigration {
            // RULE 4: If source list has NO active elements, skip popup automatically!
            let sourceTasks = allTasks.filter { $0.intervalType == migration.source && !$0.completed && $0.deletedAt == nil }
            if sourceTasks.isEmpty && migration.source != "1 Year" {
                // If it was day migration that was skipped, check if hourly migration has tasks
                if migration.source == "1 Week" {
                    let dayTasks = allTasks.filter { $0.intervalType == "1 Day" && !$0.completed && $0.deletedAt == nil }
                    if !dayTasks.isEmpty {
                        self.currentMigration = Migration(source: "1 Day", dest: "1 Hour", isFirstHourOfDay: true)
                        isFirstHourAfterDayMigration = false
                    }
                }
                return
            }
            self.currentMigration = migration
        }
    }
    
    func executeMigration(migration: Migration, selectedTaskIds: Set<String>, allTasks: [TaskItem], context: ModelContext) {
        let destTasks = allTasks.filter { $0.intervalType == migration.dest && !$0.completed && $0.deletedAt == nil }
        var maxOrder = (destTasks.map { $0.order }.max() ?? -1) + 1
        
        let sourceTasks = allTasks.filter { $0.intervalType == migration.source && !$0.completed && $0.deletedAt == nil }
        
        var droppedTasks: [TaskItem] = []
        for task in sourceTasks {
            if selectedTaskIds.contains(task.id) {
                task.intervalType = migration.dest
                task.order = maxOrder
                task.updatedAt = Date()
                maxOrder += 1
            } else if migration.source == migration.dest {
                droppedTasks.append(task)
            }
        }
        
        // Register the remote delete before removing the rows locally so that a pull already
        // in flight cannot re-create them.
        if !droppedTasks.isEmpty {
            SupabaseSyncManager.shared.deleteRemote(table: "tasks", ids: droppedTasks.map { $0.id })
            for task in droppedTasks {
                context.delete(task)
            }
        }
        
        try? context.save()
        SupabaseSyncManager.shared.push()
        currentMigration = nil
        
        // RULE 3: If Day migration was just completed, trigger the first Hourly migration of the day immediately!
        if migration.source == "1 Week" && migration.dest == "1 Day" {
            let dayTasks = allTasks.filter { $0.intervalType == "1 Day" && !$0.completed && $0.deletedAt == nil }
            if !dayTasks.isEmpty {
                self.currentMigration = Migration(source: "1 Day", dest: "1 Hour", isFirstHourOfDay: true)
                isFirstHourAfterDayMigration = false
            }
        }
    }
    
    func triggerSimulatedMigration(source: String, dest: String) {
        currentMigration = Migration(source: source, dest: dest)
    }
    
    func skipMigration(allTasks: [TaskItem] = []) {
        if let m = currentMigration, m.source == "1 Week" && m.dest == "1 Day" {
            currentMigration = nil
            // If Day migration was skipped, trigger first Hourly migration of the day
            let dayTasks = allTasks.filter { $0.intervalType == "1 Day" && !$0.completed && $0.deletedAt == nil }
            if !dayTasks.isEmpty {
                self.currentMigration = Migration(source: "1 Day", dest: "1 Hour", isFirstHourOfDay: true)
                isFirstHourAfterDayMigration = false
            }
        } else {
            currentMigration = nil
        }
    }
}
