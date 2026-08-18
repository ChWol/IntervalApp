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
    public static let shared = MigrationManager()
    
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
    
    // MARK: - Synchronized Marker Storage (Local + iCloud NSUbiquitousKeyValueStore)
    
    private func getMarker(for key: String, defaultVal: String) -> String {
        let local = UserDefaults.standard.string(forKey: key)
        let cloud = NSUbiquitousKeyValueStore.default.string(forKey: key)
        
        if let l = local, let c = cloud {
            let best = max(l, c)
            if l != best {
                UserDefaults.standard.set(best, forKey: key)
            }
            return best
        }
        if let c = cloud {
            UserDefaults.standard.set(c, forKey: key)
            return c
        }
        if let l = local {
            NSUbiquitousKeyValueStore.default.set(l, forKey: key)
            return l
        }
        return defaultVal
    }
    
    private func setMarker(_ value: String, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    func startMonitoring(context: ModelContext) {
        self.modelContext = context
        cancellables.removeAll()
        
        // Initial setup for first install
        let now = Date()
        if UserDefaults.standard.string(forKey: StoreKey.lastHandledHour) == nil &&
           NSUbiquitousKeyValueStore.default.string(forKey: StoreKey.lastHandledHour) == nil {
            setMarker(Self.hourFormatter.string(from: now), for: StoreKey.lastHandledHour)
            setMarker(Self.dayFormatter.string(from: now), for: StoreKey.lastHandledDay)
            setMarker(Self.weekFormatter.string(from: now), for: StoreKey.lastHandledWeek)
            setMarker(Self.monthFormatter.string(from: now), for: StoreKey.lastHandledMonth)
            setMarker(Self.yearFormatter.string(from: now), for: StoreKey.lastHandledYear)
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
            
        // 3. React when iCloud Key-Value store syncs markers from other devices
        NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .sink { [weak self] _ in
                self?.syncFromCloudStore()
            }
            .store(in: &cancellables)
        
        // 4. System calendar and clock notifications
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
    
    private func syncFromCloudStore() {
        let keys = [
            StoreKey.lastHandledHour,
            StoreKey.lastHandledDay,
            StoreKey.lastHandledWeek,
            StoreKey.lastHandledMonth,
            StoreKey.lastHandledYear
        ]
        for key in keys {
            if let cloudVal = NSUbiquitousKeyValueStore.default.string(forKey: key) {
                let localVal = UserDefaults.standard.string(forKey: key) ?? ""
                if cloudVal > localVal {
                    UserDefaults.standard.set(cloudVal, forKey: key)
                }
            }
        }
        
        // If a migration is currently showing but its marker was updated from another device, dismiss it!
        if let current = currentMigration {
            let now = Date()
            let currentHour = Self.hourFormatter.string(from: now)
            let currentDay = Self.dayFormatter.string(from: now)
            let currentWeek = Self.weekFormatter.string(from: now)
            let currentMonth = Self.monthFormatter.string(from: now)
            let currentYear = Self.yearFormatter.string(from: now)
            
            var isAlreadyHandled = false
            if current.source == "1 Year" && current.dest == "1 Year" && getMarker(for: StoreKey.lastHandledYear, defaultVal: "") >= currentYear {
                isAlreadyHandled = true
            } else if current.source == "1 Year" && current.dest == "1 Month" && getMarker(for: StoreKey.lastHandledMonth, defaultVal: "") >= currentMonth {
                isAlreadyHandled = true
            } else if current.source == "1 Month" && current.dest == "1 Week" && getMarker(for: StoreKey.lastHandledWeek, defaultVal: "") >= currentWeek {
                isAlreadyHandled = true
            } else if current.source == "1 Week" && current.dest == "1 Day" && getMarker(for: StoreKey.lastHandledDay, defaultVal: "") >= currentDay {
                isAlreadyHandled = true
            } else if current.dest == HabitTaskLink.hourInterval && getMarker(for: StoreKey.lastHandledHour, defaultVal: "") >= currentHour {
                isAlreadyHandled = true
            }
            
            if isAlreadyHandled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.currentMigration = nil
                }
            }
        }
        
        self.checkMigrations()
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
        
        let now = Date()
        
        let currentYear = Self.yearFormatter.string(from: now)
        let currentMonth = Self.monthFormatter.string(from: now)
        let currentWeek = Self.weekFormatter.string(from: now)
        let currentDay = Self.dayFormatter.string(from: now)
        let currentHour = Self.hourFormatter.string(from: now)
        
        let lastHandledYear = getMarker(for: StoreKey.lastHandledYear, defaultVal: currentYear)
        let lastHandledMonth = getMarker(for: StoreKey.lastHandledMonth, defaultVal: currentMonth)
        let lastHandledWeek = getMarker(for: StoreKey.lastHandledWeek, defaultVal: currentWeek)
        let lastHandledDay = getMarker(for: StoreKey.lastHandledDay, defaultVal: currentDay)
        let lastHandledHour = getMarker(for: StoreKey.lastHandledHour, defaultVal: currentHour)
        
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
            setMarker(marker, for: key)
            SoundManager.playTransitionChime()
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
                setMarker(marker, for: key)
                presentFirstHourOfDay()
            } else if migration.source == "1 Year" && migration.dest == "1 Month" {
                setMarker(marker, for: key)
            } else if migration.source == "1 Month" && migration.dest == "1 Week" {
                setMarker(marker, for: key)
            }
        }
    }
    
    private func presentFirstHourOfDay() {
        let tasks = activeTasks()
        let sourceCount = tasks.filter { $0.intervalType == "1 Day" }.count
        let habitCount = selectableHabits(tasks: tasks).count
        
        let migration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval, isFirstHourOfDay: true)
        if MigrationSchedule.shouldPresent(migration, sourceTaskCount: sourceCount, selectableHabitCount: habitCount) {
            let currentHour = Self.hourFormatter.string(from: Date())
            setMarker(currentHour, for: StoreKey.lastHandledHour)
            SoundManager.playTransitionChime()
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
            } else {
                droppedTasks.append(task)
            }
        }
        
        if migration.dest == HabitTaskLink.hourInterval && !selectedHabitIds.isEmpty {
            let hourHabitTasks = HabitTaskLink.createTasksForSelectedHabits(
                selectedHabitIds: selectedHabitIds,
                allHabits: allHabits,
                existingTasks: allTasks,
                startingOrder: maxOrder
            )
            for newTask in hourHabitTasks {
                context.insert(newTask)
            }
        }
        
        if !droppedTasks.isEmpty {
            TaskHousekeeping.softDelete(droppedTasks, in: context, now: now)
        }
        
        try? context.save()
        SupabaseSyncManager.shared.push()
        
        let completedMigration = currentMigration
        withAnimation(.easeInOut(duration: 0.15)) {
            currentMigration = nil
        }
        
        if let completedMigration, completedMigration.source == "1 Week" && completedMigration.dest == "1 Day" {
            presentFirstHourOfDay()
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
