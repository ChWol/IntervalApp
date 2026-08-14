import Foundation
import SwiftData
import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

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
        static let lastHandledHour = "lastHandledHourMarker_v2"
        static let lastHandledDay = "lastHandledDayMarker_v2"
        static let lastHandledWeek = "lastHandledWeekMarker_v2"
        static let lastHandledMonth = "lastHandledMonthMarker_v2"
        static let lastHandledYear = "lastHandledYearMarker_v2"
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var isFirstHourAfterDayMigration = false
    private var modelContext: ModelContext?
    
    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HH"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    private static let weekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-'W'ww"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    func startMonitoring(context: ModelContext) {
        self.modelContext = context
        cancellables.removeAll()
        
        // Initial setup for first install
        let defaults = UserDefaults.standard
        let now = Date()
        if defaults.string(forKey: StoreKey.lastHandledHour) == nil {
            defaults.set(Self.hourFormatter.string(from: now), forKey: StoreKey.lastHandledHour)
            defaults.set(Self.dayFormatter.string(from: now), forKey: StoreKey.lastHandledDay)
            defaults.set(Self.weekFormatter.string(from: now), forKey: StoreKey.lastHandledWeek)
            defaults.set(Self.monthFormatter.string(from: now), forKey: StoreKey.lastHandledMonth)
            defaults.set(Self.yearFormatter.string(from: now), forKey: StoreKey.lastHandledYear)
        }
        
        // Check migrations on launch
        checkMigrations()
        
        // 1. Regular 10-second check
        Timer.publish(every: 10.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkMigrations()
            }
            .store(in: &cancellables)
        
        // 2. React when Supabase sync finishes pulling fresh remote tasks/habits
        NotificationCenter.default.publisher(for: .syncPullDidComplete)
            .sink { [weak self] _ in
                self?.checkMigrations()
            }
            .store(in: &cancellables)
        
        // 3. System calendar and clock notifications
        #if os(macOS)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.checkMigrations() }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.checkMigrations() }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .sink { [weak self] _ in self?.checkMigrations() }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
            .sink { [weak self] _ in self?.checkMigrations() }
            .store(in: &cancellables)
        #else
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.checkMigrations() }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .sink { [weak self] _ in self?.checkMigrations() }
            .store(in: &cancellables)
        #endif
        
        scheduleNextHourTimer()
    }
    
    private func scheduleNextHourTimer() {
        let now = Date()
        let cal = Calendar.current
        guard let nextHour = cal.nextDate(after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) else { return }
        
        let interval = max(1.0, nextHour.timeIntervalSince(now))
        
        Just(())
            .delay(for: .seconds(interval), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.checkMigrations()
                self.scheduleNextHourTimer()
            }
            .store(in: &cancellables)
    }
    
    func checkMigrations() {
        guard currentMigration == nil else { return }
        guard let _ = modelContext else { return }
        
        let defaults = UserDefaults.standard
        let now = Date()
        
        let currentYear = Self.yearFormatter.string(from: now)
        let currentMonth = Self.monthFormatter.string(from: now)
        let currentWeek = Self.weekFormatter.string(from: now)
        let currentDay = Self.dayFormatter.string(from: now)
        let currentHour = Self.hourFormatter.string(from: now)
        
        let lastHandledYear = defaults.string(forKey: StoreKey.lastHandledYear) ?? currentYear
        let lastHandledMonth = defaults.string(forKey: StoreKey.lastHandledMonth) ?? currentMonth
        let lastHandledWeek = defaults.string(forKey: StoreKey.lastHandledWeek) ?? currentWeek
        let lastHandledDay = defaults.string(forKey: StoreKey.lastHandledDay) ?? currentDay
        let lastHandledHour = defaults.string(forKey: StoreKey.lastHandledHour) ?? currentHour
        
        var pending: Migration? = nil
        var targetStoreKey: String? = nil
        var targetMarker: String? = nil
        
        if lastHandledYear != currentYear {
            pending = Migration(source: "1 Year", dest: "1 Year")
            targetStoreKey = StoreKey.lastHandledYear
            targetMarker = currentYear
        } else if lastHandledMonth != currentMonth {
            pending = Migration(source: "1 Year", dest: "1 Month")
            targetStoreKey = StoreKey.lastHandledMonth
            targetMarker = currentMonth
        } else if lastHandledWeek != currentWeek {
            pending = Migration(source: "1 Month", dest: "1 Week")
            targetStoreKey = StoreKey.lastHandledWeek
            targetMarker = currentWeek
        } else if lastHandledDay != currentDay {
            pending = Migration(source: "1 Week", dest: "1 Day")
            targetStoreKey = StoreKey.lastHandledDay
            targetMarker = currentDay
        } else if lastHandledHour != currentHour {
            pending = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval, isFirstHourOfDay: isFirstHourAfterDayMigration)
            targetStoreKey = StoreKey.lastHandledHour
            targetMarker = currentHour
        }
        
        guard let migration = pending, let key = targetStoreKey, let marker = targetMarker else { return }
        
        let tasks = activeTasks()
        let sourceCount = tasks.filter { $0.intervalType == migration.source }.count
        let habitCount = migration.dest == HabitTaskLink.hourInterval ? selectableHabits(tasks: tasks).count : 0
        
        if MigrationSchedule.shouldPresent(migration, sourceTaskCount: sourceCount, selectableHabitCount: habitCount) {
            defaults.set(marker, forKey: key)
            withAnimation(.easeInOut(duration: 0.2)) {
                currentMigration = migration
            }
            if migration.source == "1 Week" && migration.dest == "1 Day" {
                isFirstHourAfterDayMigration = true
            }
            if migration.dest == HabitTaskLink.hourInterval {
                isFirstHourAfterDayMigration = false
            }
        } else {
            // Source list is empty (and for hour migration, uncompleted habits for today are also empty)
            if migration.source == "1 Week" && migration.dest == "1 Day" {
                defaults.set(marker, forKey: key)
                presentFirstHourOfDay()
            } else if migration.source == "1 Year" && migration.dest == "1 Month" {
                defaults.set(marker, forKey: key)
            } else if migration.source == "1 Month" && migration.dest == "1 Week" {
                defaults.set(marker, forKey: key)
            }
            // For hour migration: if sourceCount == 0 && habitCount == 0, we don't consume the key immediately
            // so that if tasks sync from the cloud a second later during this hour, it can still trigger.
        }
    }
    
    private func presentFirstHourOfDay() {
        let tasks = activeTasks()
        let sourceCount = tasks.filter { $0.intervalType == "1 Day" }.count
        let habitCount = selectableHabits(tasks: tasks).count
        
        let migration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval, isFirstHourOfDay: true)
        if MigrationSchedule.shouldPresent(migration, sourceTaskCount: sourceCount, selectableHabitCount: habitCount) {
            let currentHour = Self.hourFormatter.string(from: Date())
            UserDefaults.standard.set(currentHour, forKey: StoreKey.lastHandledHour)
            withAnimation(.easeInOut(duration: 0.2)) {
                currentMigration = migration
            }
            isFirstHourAfterDayMigration = false
        }
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
        
        if !droppedTasks.isEmpty {
            SupabaseSyncManager.shared.deleteRemote(table: SyncTable.tasks, ids: droppedTasks.map { $0.id })
            for task in droppedTasks {
                context.delete(task)
            }
        }
        
        try? context.save()
        SupabaseSyncManager.shared.push()
        withAnimation(.easeInOut(duration: 0.15)) {
            currentMigration = nil
        }
        
        // Once the day is planned, move straight on to the first hour of that day if tasks/habits exist
        if migration.source == "1 Week" && migration.dest == "1 Day" {
            presentFirstHourOfDay()
        }
    }
    
    func triggerSimulatedMigration(source: String, dest: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentMigration = Migration(source: source, dest: dest)
        }
    }
    
    func skipMigration() {
        let skipped = currentMigration
        withAnimation(.easeInOut(duration: 0.15)) {
            currentMigration = nil
        }
        
        if let skipped, skipped.source == "1 Week" && skipped.dest == "1 Day" {
            presentFirstHourOfDay()
        }
    }
    
    #if DEBUG
    func attachForTesting(context: ModelContext) {
        modelContext = context
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
