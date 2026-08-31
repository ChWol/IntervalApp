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
    private var pendingMarkerKey: String?
    private var pendingMarkerValue: String?
    
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
    
    private var dayStartHour: Int {
        if UserDefaults.standard.object(forKey: "dayStartHour") != nil {
            return UserDefaults.standard.integer(forKey: "dayStartHour")
        }
        return 6 // Default 6 AM as requested
    }
    
    private var dayStartMinute: Int {
        return UserDefaults.standard.integer(forKey: "dayStartMinute")
    }
    
    private static var weekFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-'W'ww"
        f.locale = Locale(identifier: "en_US_POSIX")
        var cal = Calendar(identifier: .iso8601)
        let weekStart = UserDefaults.standard.string(forKey: "weekStartDay") ?? "Monday"
        cal.firstWeekday = (weekStart == "Sunday") ? 1 : 2
        cal.minimumDaysInFirstWeek = 4
        cal.timeZone = TimeZone.current
        f.calendar = cal
        f.timeZone = TimeZone.current
        return f
    }
    
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
    
    // MARK: - Synchronized Marker Storage (Local UserDefaults + Supabase user_metadata)
    
    func applyRemoteMarkers(_ markers: [String: String]) {
        var didUpdate = false
        for (key, val) in markers {
            let local = UserDefaults.standard.string(forKey: key) ?? ""
            if val >= local {
                UserDefaults.standard.set(val, forKey: key)
                didUpdate = true
            }
        }
        if didUpdate {
            // If another device already handled this migration, dismiss the active modal immediately!
            if let current = currentMigration {
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
                
                var isAlreadyHandled = false
                if current.dest == HabitTaskLink.hourInterval && lastHandledHour == currentHour {
                    isAlreadyHandled = true
                } else if current.source == "1 Week" && current.dest == "1 Day" && lastHandledDay == currentDay {
                    isAlreadyHandled = true
                } else if current.source == "1 Month" && current.dest == "1 Week" && lastHandledWeek == currentWeek {
                    isAlreadyHandled = true
                } else if current.source == "1 Year" && current.dest == "1 Month" && lastHandledMonth == currentMonth {
                    isAlreadyHandled = true
                } else if current.source == "1 Year" && current.dest == "1 Year" && lastHandledYear == currentYear {
                    isAlreadyHandled = true
                }
                
                if isAlreadyHandled {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.currentMigration = nil
                    }
                }
            }
            checkMigrations()
        }
    }
    
    private func getMarker(for key: String, defaultVal: String) -> String {
        return UserDefaults.standard.string(forKey: key) ?? defaultVal
    }
    
    private func setMarker(_ value: String, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
        Task { @MainActor in
            await SupabaseSyncManager.shared.updateUserMetadata([key: value])
        }
    }
    
    func startMonitoring(context: ModelContext) {
        self.modelContext = context
        cancellables.removeAll()
        
        // Initial setup for first install
        let now = Date()
        if UserDefaults.standard.string(forKey: StoreKey.lastHandledHour) == nil {
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
        #elseif os(iOS)
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
        
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        
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
        
        let minute = Calendar.current.component(.minute, from: now)
        let isPastDayStart = (hour > dayStartHour) || (hour == dayStartHour && minute >= dayStartMinute)
        
        // Day, Week, Month, and Year migrations trigger at or after the configured day start time (default 06:00)
        // to avoid interrupting night work sessions.
        if isPastDayStart {
            if lastHandledYear != currentYear {
                performBoundaryRollover(for: "1 Year")
                pending = Migration(source: "1 Year", dest: "1 Year")
                targetStoreKey = StoreKey.lastHandledYear
                targetMarker = currentYear
            } else if lastHandledMonth != currentMonth {
                performBoundaryRollover(for: "1 Month")
                pending = Migration(source: "1 Year", dest: "1 Month")
                targetStoreKey = StoreKey.lastHandledMonth
                targetMarker = currentMonth
            } else if lastHandledWeek != currentWeek {
                performBoundaryRollover(for: "1 Week")
                pending = Migration(source: "1 Month", dest: "1 Week")
                targetStoreKey = StoreKey.lastHandledWeek
                targetMarker = currentWeek
            } else if lastHandledDay != currentDay {
                performBoundaryRollover(for: "1 Day")
                pending = Migration(source: "1 Week", dest: "1 Day")
                targetStoreKey = StoreKey.lastHandledDay
                targetMarker = currentDay
            }
        }
        
        if pending == nil && lastHandledHour != currentHour {
            pending = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval, isFirstHourOfDay: isFirstHourAfterDayMigration)
            targetStoreKey = StoreKey.lastHandledHour
            targetMarker = currentHour
        }
        
        guard let migration = pending, let key = targetStoreKey, let marker = targetMarker else { return }
        
        let tasks = activeTasks()
        let sourceCount = tasks.filter { $0.intervalType == migration.source }.count
        let habitCount = migration.dest == HabitTaskLink.hourInterval ? selectableHabits(tasks: tasks).count : 0
        let reverseTasks = TaskAgingHelper.findLingeringTasks(for: migration, in: tasks)
        let reverseCount = reverseTasks.count
        
        if MigrationSchedule.shouldPresent(migration, sourceTaskCount: sourceCount, selectableHabitCount: habitCount, reverseTaskCount: reverseCount) {
            // Marker is set AFTER the user commits or skips, not here.
            // Store pending marker info so executeMigration/skipMigration can commit it.
            pendingMarkerKey = key
            pendingMarkerValue = marker
            SoundManager.playTransitionChime()
            NotificationManager.shared.sendMigrationNotification(for: migration)
            NotificationManager.shared.scheduleUpcomingBoundaryNotifications()
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
        cleanUpPreviousDayHabitTasks()
        let tasks = activeTasks()
        let sourceCount = tasks.filter { $0.intervalType == "1 Day" }.count
        let habitCount = selectableHabits(tasks: tasks).count
        let migration = Migration(source: "1 Day", dest: HabitTaskLink.hourInterval, isFirstHourOfDay: true)
        let reverseTasks = TaskAgingHelper.findLingeringTasks(for: migration, in: tasks)
        let reverseCount = reverseTasks.count
        
        if MigrationSchedule.shouldPresent(migration, sourceTaskCount: sourceCount, selectableHabitCount: habitCount, reverseTaskCount: reverseCount) {
            let currentHour = Self.hourFormatter.string(from: Date())
            pendingMarkerKey = StoreKey.lastHandledHour
            pendingMarkerValue = currentHour
            SoundManager.playTransitionChime()
            NotificationManager.shared.sendMigrationNotification(for: migration)
            NotificationManager.shared.scheduleUpcomingBoundaryNotifications()
            withAnimation(.easeInOut(duration: 0.2)) {
                currentMigration = migration
            }
            isFirstHourAfterDayMigration = false
        }
    }
    
    func executeMigration(migration: Migration,
                          selectedTaskIds: Set<String>,
                          selectedHabitIds: Set<String> = [],
                          selectedReverseTaskIds: Set<String> = []) {
        guard let context = modelContext else {
            currentMigration = nil
            return
        }
        
        // Commit the pending marker now that the user has taken action
        if let key = pendingMarkerKey, let value = pendingMarkerValue {
            setMarker(value, for: key)
            pendingMarkerKey = nil
            pendingMarkerValue = nil
        }
        
        let allTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let allHabits = (try? context.fetch(FetchDescriptor<HabitItem>())) ?? []
        let active = allTasks.filter { !$0.completed && $0.deletedAt == nil }
        
        var maxOrder = (active.filter { $0.intervalType == migration.dest }.map { $0.order }.max() ?? -1) + 1
        let now = Date()
        
        // 1. Forward Migration: Move selected tasks from source to dest
        for task in active where task.intervalType == migration.source {
            if selectedTaskIds.contains(task.id) {
                task.intervalType = migration.dest
                task.order = maxOrder
                task.updatedAt = now
                maxOrder += 1
            }
            // Non-selected tasks stay in their source interval – they are NOT deleted.
        }
        
        // 2. Reverse Demotion: Move selected lingering tasks from dest to parent interval
        if let parent = TaskAgingHelper.parentInterval(for: migration.dest), !selectedReverseTaskIds.isEmpty {
            var parentMaxOrder = (active.filter { $0.intervalType == parent }.map { $0.order }.max() ?? -1) + 1
            for task in active where task.intervalType == migration.dest {
                if selectedReverseTaskIds.contains(task.id) {
                    task.intervalType = parent
                    task.order = parentMaxOrder
                    task.updatedAt = now
                    parentMaxOrder += 1
                }
            }
        }
        
        // 3. Habits to Hour Tasks
        if migration.dest == HabitTaskLink.hourInterval && !selectedHabitIds.isEmpty {
            let chosenHabits = allHabits.filter { selectedHabitIds.contains($0.id) }
            let hourHabitTasks = HabitTaskLink.makeHourTasks(
                for: chosenHabits,
                existingHourTasks: allTasks.filter { $0.intervalType == HabitTaskLink.hourInterval },
                startingOrder: maxOrder,
                now: now
            )
            for newTask in hourHabitTasks {
                context.insert(newTask)
            }
        }
        
        try? context.save()
        SupabaseSyncManager.shared.push()
        
        let completedMigration = currentMigration
        withAnimation(.easeInOut(duration: 0.15)) {
            currentMigration = nil
        }
        
        if let completedMigration, completedMigration.source == "1 Week" && completedMigration.dest == "1 Day" {
            cleanUpPreviousDayHabitTasks()
            presentFirstHourOfDay()
        }
    }
    
    func skipMigration() {
        // Commit the pending marker now that the user has skipped
        if let key = pendingMarkerKey, let value = pendingMarkerValue {
            setMarker(value, for: key)
            pendingMarkerKey = nil
            pendingMarkerValue = nil
        }
        
        let skipped = currentMigration
        withAnimation(.easeInOut(duration: 0.15)) {
            currentMigration = nil
        }
        
        if let skipped, skipped.source == "1 Week" && skipped.dest == "1 Day" {
            cleanUpPreviousDayHabitTasks()
            presentFirstHourOfDay()
        }
    }
    
    private func performBoundaryRollover(for targetInterval: String) {
        guard let context = modelContext else { return }
        let allTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let active = allTasks.filter { !$0.completed && $0.deletedAt == nil }
        let now = Date()
        var didModify = false
        
        let subordinateIntervals: [String]
        switch targetInterval {
        case "1 Year":
            subordinateIntervals = ["1 Month", "1 Week", "1 Day", HabitTaskLink.hourInterval]
        case "1 Month":
            subordinateIntervals = ["1 Week", "1 Day", HabitTaskLink.hourInterval]
        case "1 Week":
            subordinateIntervals = ["1 Day", HabitTaskLink.hourInterval]
        case "1 Day":
            subordinateIntervals = [HabitTaskLink.hourInterval]
        default:
            subordinateIntervals = []
        }
        
        var maxOrder = (active.filter { $0.intervalType == targetInterval }.map { $0.order }.max() ?? -1) + 1
        
        // Collect tasks to roll over (excluding habit-linked tasks)
        let tasksToRollOver = active.filter { subordinateIntervals.contains($0.intervalType) && $0.habitId == nil }
        
        if !tasksToRollOver.isEmpty {
            // Shift existing tasks in the target interval DOWN so rolled-over tasks appear on top
            let existingTargetTasks = active.filter { $0.intervalType == targetInterval }.sorted { $0.order < $1.order }
            let rollOverCount = tasksToRollOver.count
            for existingTask in existingTargetTasks {
                existingTask.order += rollOverCount
                existingTask.updatedAt = now
            }
            
            // Place rolled-over tasks at the top with sequential order starting from 0
            for (index, task) in tasksToRollOver.enumerated() {
                task.intervalType = targetInterval
                task.order = index
                task.updatedAt = now
            }
            didModify = true
        }
        
        // Also clean up any lingering temporary habit tasks from previous periods in 1 Hour
        if targetInterval == "1 Day" || targetInterval == "1 Week" || targetInterval == "1 Month" || targetInterval == "1 Year" {
            for task in allTasks where task.habitId != nil && !task.completed && task.deletedAt == nil {
                task.deletedAt = now
                task.updatedAt = now
                didModify = true
            }
        }
        
        if didModify {
            try? context.save()
            SupabaseSyncManager.shared.push()
        }
    }
    
    private func cleanUpPreviousDayHabitTasks() {
        guard let context = modelContext else { return }
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let now = Date()
        var didClean = false
        for task in all where task.habitId != nil && !task.completed && task.deletedAt == nil {
            task.deletedAt = now
            task.updatedAt = now
            didClean = true
        }
        if didClean {
            try? context.save()
            SupabaseSyncManager.shared.push()
        }
    }
    
    #if DEBUG
    func attachForTesting(context: ModelContext) {
        modelContext = context
    }
    
    func testingPerformBoundaryRollover(for targetInterval: String) {
        performBoundaryRollover(for: targetInterval)
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
