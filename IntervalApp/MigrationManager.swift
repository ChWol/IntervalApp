import Foundation
import SwiftData
import SwiftUI
import Combine
struct Migration {
    let source: String
    let dest: String
}

class MigrationManager: ObservableObject {
    @Published var currentMigration: Migration? = nil
    private var migrationQueue: [Migration] = []
    
    func checkMigrations() {
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
        } else if let lh = lastHour, lh != currentHour {
            pendingMigration = Migration(source: "1 Day", dest: "1 Hour")
        }
        
        // Save latest state
        defaults.set(currentHour, forKey: "lastHour")
        defaults.set(currentDay, forKey: "lastDay")
        defaults.set(currentWeek, forKey: "lastWeek")
        defaults.set(currentMonth, forKey: "lastMonth")
        defaults.set(currentYear, forKey: "lastYear")
        
        if let migration = pendingMigration {
            self.currentMigration = migration
        }
    }
    
    func executeMigration(migration: Migration, selectedTaskIds: Set<String>, allTasks: [TaskItem], context: ModelContext) {
        let destTasks = allTasks.filter { $0.intervalType == migration.dest && !$0.completed && $0.deletedAt == nil }
        var maxOrder = (destTasks.map { $0.order }.max() ?? -1) + 1
        
        let sourceTasks = allTasks.filter { $0.intervalType == migration.source && !$0.completed && $0.deletedAt == nil }
        
        for task in sourceTasks {
            if selectedTaskIds.contains(task.id) {
                task.intervalType = migration.dest
                task.order = maxOrder
                maxOrder += 1
            } else if migration.source == migration.dest {
                context.delete(task)
            }
        }
        
        try? context.save()
        currentMigration = nil
    }
    
    func triggerSimulatedMigration(source: String, dest: String) {
        currentMigration = Migration(source: source, dest: dest)
    }
    
    func skipMigration() {
        currentMigration = nil
    }
}
