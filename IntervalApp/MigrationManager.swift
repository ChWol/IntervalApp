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
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let currentDay = formatter.string(from: now)
        
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: now)
        let year = cal.component(.yearForWeekOfYear, from: now)
        let currentWeek = "\(year)-W\(week)"
        
        formatter.dateFormat = "yyyy-MM"
        let currentMonth = formatter.string(from: now)
        
        formatter.dateFormat = "yyyy"
        let currentYear = formatter.string(from: now)
        
        var queue: [Migration] = []
        
        if let lastYear = defaults.string(forKey: "lastYear"), lastYear != currentYear {
            queue.append(Migration(source: "1 Year", dest: "1 Year"))
        }
        if let lastMonth = defaults.string(forKey: "lastMonth"), lastMonth != currentMonth {
            queue.append(Migration(source: "1 Year", dest: "1 Month"))
        }
        if let lastWeek = defaults.string(forKey: "lastWeek"), lastWeek != currentWeek {
            queue.append(Migration(source: "1 Month", dest: "1 Week"))
        }
        if let lastDay = defaults.string(forKey: "lastDay"), lastDay != currentDay {
            queue.append(Migration(source: "1 Week", dest: "1 Day"))
        }
        
        defaults.set(currentYear, forKey: "lastYear")
        defaults.set(currentMonth, forKey: "lastMonth")
        defaults.set(currentWeek, forKey: "lastWeek")
        defaults.set(currentDay, forKey: "lastDay")
        
        if !queue.isEmpty {
            self.migrationQueue = queue
            self.currentMigration = queue.first
        }
    }
    
    func executeMigration(migration: Migration, selectedTaskIds: Set<String>, allTasks: [TaskItem], context: ModelContext) {
        let sourceTasks = allTasks.filter { $0.intervalType == migration.source }
        
        for task in sourceTasks {
            if selectedTaskIds.contains(task.id) {
                task.intervalType = migration.dest
            } else if migration.source == migration.dest {
                context.delete(task)
            }
        }
        
        try? context.save()
        advanceQueue()
    }
    
    func triggerSimulatedMigration(source: String, dest: String) {
        currentMigration = Migration(source: source, dest: dest)
    }
    
    func skipMigration() {
        advanceQueue()
    }
    
    private func advanceQueue() {
        if !migrationQueue.isEmpty {
            migrationQueue.removeFirst()
            currentMigration = migrationQueue.first
        } else {
            currentMigration = nil
        }
    }
}
