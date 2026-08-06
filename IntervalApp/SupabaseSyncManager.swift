import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - Supabase DTOs

struct SupabaseTaskDTO: Codable {
    let id: String
    let text: String
    let completed: Bool
    let created_at: String
    let interval_type: String
    let order: Int
    let deleted_at: String?
    let completed_at: String?
    let sync_key: String
    let updated_at: String
}

struct SupabaseHabitDTO: Codable {
    let id: String
    let text: String
    let frequency: String
    let streak: Int
    let last_completed_date: String?
    let order: Int
    let sync_key: String
    let updated_at: String
}

// MARK: - Supabase Sync Manager

@MainActor
class SupabaseSyncManager: ObservableObject {
    static let shared = SupabaseSyncManager()
    
    private let supabaseURL = "https://mrqgudqemlgdxnrqxqtk.supabase.co"
    private let supabaseKey = "sb_publishable_KV6DvqpKbl6wmMZvcwPczw_ID2hOShH"
    
    @Published var syncKey: String {
        didSet {
            UserDefaults.standard.set(syncKey, forKey: "supabase_sync_key")
            isConfigured = !syncKey.isEmpty
        }
    }
    @Published var isConfigured: Bool
    
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var isSyncing = false
    
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private init() {
        let key = UserDefaults.standard.string(forKey: "supabase_sync_key") ?? ""
        self.syncKey = key
        self.isConfigured = !key.isEmpty
    }
    
    // MARK: - Public API
    
    func configure(syncKey: String) {
        self.syncKey = syncKey
    }
    
    func start(context: ModelContext) {
        self.modelContext = context
        guard isConfigured else { return }
        
        // Periodic pull every 5 seconds
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.pullFromSupabase()
                }
            }
            .store(in: &cancellables)
        
        // Listen for app becoming active
        #if os(macOS)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.pullFromSupabase()
                }
            }
            .store(in: &cancellables)
        #else
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.pullFromSupabase()
                }
            }
            .store(in: &cancellables)
        #endif
        
        // Initial push + pull
        Task {
            await pushToSupabase()
            await pullFromSupabase()
        }
    }
    
    /// Fire-and-forget push (call from sync contexts)
    func push() {
        guard isConfigured else { return }
        Task { @MainActor in
            await pushToSupabase()
        }
    }
    
    // MARK: - Push to Supabase
    
    private func pushToSupabase() async {
        guard !isSyncing, isConfigured, let context = modelContext else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        let now = dateFormatter.string(from: Date())
        
        // Push tasks
        let taskDescriptor = FetchDescriptor<TaskItem>()
        let tasks = (try? context.fetch(taskDescriptor)) ?? []
        
        let taskDTOs = tasks.map { task in
            SupabaseTaskDTO(
                id: task.id,
                text: task.text,
                completed: task.completed,
                created_at: dateFormatter.string(from: task.createdAt),
                interval_type: task.intervalType,
                order: task.order,
                deleted_at: task.deletedAt.map { dateFormatter.string(from: $0) },
                completed_at: task.completedAt.map { dateFormatter.string(from: $0) },
                sync_key: syncKey,
                updated_at: now
            )
        }
        
        if !taskDTOs.isEmpty {
            await upsert(table: "tasks", items: taskDTOs)
        }
        
        // Push habits
        let habitDescriptor = FetchDescriptor<HabitItem>()
        let habits = (try? context.fetch(habitDescriptor)) ?? []
        
        let habitDTOs = habits.map { habit in
            SupabaseHabitDTO(
                id: habit.id,
                text: habit.text,
                frequency: habit.frequency,
                streak: habit.streak,
                last_completed_date: habit.lastCompletedDate.map { dateFormatter.string(from: $0) },
                order: habit.order,
                sync_key: syncKey,
                updated_at: now
            )
        }
        
        if !habitDTOs.isEmpty {
            await upsert(table: "habits", items: habitDTOs)
        }
    }
    
    // MARK: - Pull from Supabase
    
    private func pullFromSupabase() async {
        guard !isSyncing, isConfigured, let context = modelContext else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        // Pull tasks
        if let remoteTasks: [SupabaseTaskDTO] = await fetch(table: "tasks") {
            let descriptor = FetchDescriptor<TaskItem>()
            let existingTasks = (try? context.fetch(descriptor)) ?? []
            let existingDict = Dictionary(uniqueKeysWithValues: existingTasks.map { ($0.id, $0) })
            
            for dto in remoteTasks {
                if let existing = existingDict[dto.id] {
                    existing.text = dto.text
                    existing.completed = dto.completed
                    existing.intervalType = dto.interval_type
                    existing.order = dto.order
                    existing.createdAt = dateFormatter.date(from: dto.created_at) ?? existing.createdAt
                    existing.deletedAt = dto.deleted_at.flatMap { dateFormatter.date(from: $0) }
                    existing.completedAt = dto.completed_at.flatMap { dateFormatter.date(from: $0) }
                } else {
                    let newTask = TaskItem(text: dto.text, intervalType: dto.interval_type, order: dto.order)
                    newTask.id = dto.id
                    newTask.completed = dto.completed
                    newTask.createdAt = dateFormatter.date(from: dto.created_at) ?? Date()
                    newTask.deletedAt = dto.deleted_at.flatMap { dateFormatter.date(from: $0) }
                    newTask.completedAt = dto.completed_at.flatMap { dateFormatter.date(from: $0) }
                    context.insert(newTask)
                }
            }
        }
        
        // Pull habits
        if let remoteHabits: [SupabaseHabitDTO] = await fetch(table: "habits") {
            let descriptor = FetchDescriptor<HabitItem>()
            let existingHabits = (try? context.fetch(descriptor)) ?? []
            let existingDict = Dictionary(uniqueKeysWithValues: existingHabits.map { ($0.id, $0) })
            
            for dto in remoteHabits {
                if let existing = existingDict[dto.id] {
                    existing.text = dto.text
                    existing.frequency = dto.frequency
                    existing.streak = dto.streak
                    existing.lastCompletedDate = dto.last_completed_date.flatMap { dateFormatter.date(from: $0) }
                    existing.order = dto.order
                } else {
                    let newHabit = HabitItem(text: dto.text, frequency: dto.frequency, order: dto.order)
                    newHabit.id = dto.id
                    newHabit.streak = dto.streak
                    newHabit.lastCompletedDate = dto.last_completed_date.flatMap { dateFormatter.date(from: $0) }
                    context.insert(newHabit)
                }
            }
        }
        
        try? context.save()
    }
    
    // MARK: - HTTP Helpers
    
    private func upsert<T: Encodable>(table: String, items: [T]) async {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/\(table)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        
        do {
            request.httpBody = try JSONEncoder().encode(items)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                print("[Supabase] Upsert \(table) failed: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("[Supabase] Upsert \(table) error: \(error)")
        }
    }
    
    private func fetch<T: Decodable>(table: String) async -> [T]? {
        let encodedKey = syncKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? syncKey
        guard let url = URL(string: "\(supabaseURL)/rest/v1/\(table)?sync_key=eq.\(encodedKey)&select=*") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                print("[Supabase] Fetch \(table) failed: HTTP \(httpResponse.statusCode)")
                return nil
            }
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            print("[Supabase] Fetch \(table) error: \(error)")
            return nil
        }
    }
}
