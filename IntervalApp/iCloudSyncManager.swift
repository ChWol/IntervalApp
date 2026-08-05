import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - DTO Structs for iCloud Encoding

struct TaskDTO: Codable, Identifiable {
    let id: String
    let text: String
    let completed: Bool
    let createdAt: Date
    let intervalType: String
    let order: Int
    let deletedAt: Date?
    let completedAt: Date?
    
    init(from item: TaskItem) {
        self.id = item.id
        self.text = item.text
        self.completed = item.completed
        self.createdAt = item.createdAt
        self.intervalType = item.intervalType
        self.order = item.order
        self.deletedAt = item.deletedAt
        self.completedAt = item.completedAt
    }
}

struct HabitDTO: Codable, Identifiable {
    let id: String
    let text: String
    let frequency: String
    let streak: Int
    let lastCompletedDate: Date?
    let order: Int
    
    init(from item: HabitItem) {
        self.id = item.id
        self.text = item.text
        self.frequency = item.frequency
        self.streak = item.streak
        self.lastCompletedDate = item.lastCompletedDate
        self.order = item.order
    }
}

// MARK: - Free iCloud Sync Manager (NSUbiquitousKeyValueStore)

@MainActor
class iCloudSyncManager: ObservableObject {
    static let shared = iCloudSyncManager()
    
    private var cancellables = Set<AnyCancellable>()
    private var modelContext: ModelContext? = nil
    private var isSyncing: Bool = false
    
    private init() {}
    
    func start(context: ModelContext) {
        self.modelContext = context
        
        // Listen for remote iCloud changes from other devices
        NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, let context = self.modelContext else { return }
                self.pullFromiCloud(context: context)
            }
            .store(in: &cancellables)
        
        // Synchronize store
        NSUbiquitousKeyValueStore.default.synchronize()
        
        // Perform initial pull & push
        pullFromiCloud(context: context)
        pushToiCloud(context: context)
    }
    
    func pushToiCloud(context: ModelContext) {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let taskDescriptor = FetchDescriptor<TaskItem>()
            let tasks = (try? context.fetch(taskDescriptor)) ?? []
            let taskDTOs = tasks.map { TaskDTO(from: $0) }
            let tasksData = try JSONEncoder().encode(taskDTOs)
            
            let habitDescriptor = FetchDescriptor<HabitItem>()
            let habits = (try? context.fetch(habitDescriptor)) ?? []
            let habitDTOs = habits.map { HabitDTO(from: $0) }
            let habitsData = try JSONEncoder().encode(habitDTOs)
            
            let store = NSUbiquitousKeyValueStore.default
            store.set(tasksData, forKey: "cloud_tasks")
            store.set(habitsData, forKey: "cloud_habits")
            store.synchronize()
        } catch {
            print("[iCloudSync] Error pushing to iCloud: \(error)")
        }
    }
    
    func pullFromiCloud(context: ModelContext) {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        
        // 1. Process Tasks
        if let tasksData = store.data(forKey: "cloud_tasks"),
           let cloudTasks = try? JSONDecoder().decode([TaskDTO].self, from: tasksData) {
            
            let descriptor = FetchDescriptor<TaskItem>()
            let existingTasks = (try? context.fetch(descriptor)) ?? []
            let existingDict = Dictionary(uniqueKeysWithValues: existingTasks.map { ($0.id, $0) })
            
            var cloudIds = Set<String>()
            for dto in cloudTasks {
                cloudIds.insert(dto.id)
                if let existing = existingDict[dto.id] {
                    existing.text = dto.text
                    existing.completed = dto.completed
                    existing.createdAt = dto.createdAt
                    existing.intervalType = dto.intervalType
                    existing.order = dto.order
                    existing.deletedAt = dto.deletedAt
                    existing.completedAt = dto.completedAt
                } else {
                    let newTask = TaskItem(text: dto.text, intervalType: dto.intervalType, order: dto.order)
                    newTask.id = dto.id
                    newTask.completed = dto.completed
                    newTask.createdAt = dto.createdAt
                    newTask.deletedAt = dto.deletedAt
                    newTask.completedAt = dto.completedAt
                    context.insert(newTask)
                }
            }
            
            // Remove local tasks not in cloud
            for task in existingTasks {
                if !cloudIds.contains(task.id) {
                    context.delete(task)
                }
            }
        }
        
        // 2. Process Habits
        if let habitsData = store.data(forKey: "cloud_habits"),
           let cloudHabits = try? JSONDecoder().decode([HabitDTO].self, from: habitsData) {
            
            let descriptor = FetchDescriptor<HabitItem>()
            let existingHabits = (try? context.fetch(descriptor)) ?? []
            let existingDict = Dictionary(uniqueKeysWithValues: existingHabits.map { ($0.id, $0) })
            
            var cloudIds = Set<String>()
            for dto in cloudHabits {
                cloudIds.insert(dto.id)
                if let existing = existingDict[dto.id] {
                    existing.text = dto.text
                    existing.frequency = dto.frequency
                    existing.streak = dto.streak
                    existing.lastCompletedDate = dto.lastCompletedDate
                    existing.order = dto.order
                } else {
                    let newHabit = HabitItem(text: dto.text, frequency: dto.frequency, order: dto.order)
                    newHabit.id = dto.id
                    newHabit.streak = dto.streak
                    newHabit.lastCompletedDate = dto.lastCompletedDate
                    context.insert(newHabit)
                }
            }
            
            for habit in existingHabits {
                if !cloudIds.contains(habit.id) {
                    context.delete(habit)
                }
            }
        }
        
        try? context.save()
    }
}
