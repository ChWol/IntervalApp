import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - Auth Models

struct AuthResponse: Codable {
    let access_token: String
    let refresh_token: String
    let token_type: String
    let expires_in: Int
    let user: AuthUser
}

struct AuthUser: Codable {
    let id: String
    let email: String?
}

struct AuthErrorResponse: Codable {
    let error: String?
    let msg: String?
    let message: String?
    let error_description: String?
    
    var displayMessage: String {
        msg ?? message ?? error_description ?? error ?? "Unknown error"
    }
}

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
    let user_id: String
    let updated_at: String
}

struct SupabaseHabitDTO: Codable {
    let id: String
    let text: String
    let frequency: String
    let streak: Int
    let last_completed_date: String?
    let order: Int
    let user_id: String
    let updated_at: String
}

// MARK: - Supabase Sync Manager

@MainActor
class SupabaseSyncManager: ObservableObject {
    static let shared = SupabaseSyncManager()
    
    private let supabaseURL = "https://mrqgudqemlgdxnrqxqtk.supabase.co"
    private let supabaseKey = "sb_publishable_KV6DvqpKbl6wmMZvcwPczw_ID2hOShH"
    
    @Published var isAuthenticated: Bool = false
    @Published var userEmail: String? = nil
    @Published var authError: String? = nil
    @Published var isLoading: Bool = false
    
    // Keep isConfigured as alias for backward compat
    var isConfigured: Bool { isAuthenticated }
    
    private var accessToken: String? {
        didSet { UserDefaults.standard.set(accessToken, forKey: "sb_access_token") }
    }
    private var refreshToken: String? {
        didSet { UserDefaults.standard.set(refreshToken, forKey: "sb_refresh_token") }
    }
    private var userId: String? {
        didSet { UserDefaults.standard.set(userId, forKey: "sb_user_id") }
    }
    
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var isSyncing = false
    
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private init() {
        accessToken = UserDefaults.standard.string(forKey: "sb_access_token")
        refreshToken = UserDefaults.standard.string(forKey: "sb_refresh_token")
        userId = UserDefaults.standard.string(forKey: "sb_user_id")
        userEmail = UserDefaults.standard.string(forKey: "sb_user_email")
        isAuthenticated = accessToken != nil && userId != nil
    }
    
    // MARK: - Authentication
    
    func signUp(email: String, password: String) async {
        isLoading = true
        authError = nil
        defer { isLoading = false }
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/signup") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode >= 400 {
                if let err = try? JSONDecoder().decode(AuthErrorResponse.self, from: data) {
                    authError = err.displayMessage
                } else {
                    authError = "Registration failed (\(statusCode))"
                }
                return
            }
            
            if let authResp = try? JSONDecoder().decode(AuthResponse.self, from: data) {
                handleAuthSuccess(authResp, email: email)
            } else {
                // Email confirmation might be required
                authError = "Account created! Check your email to confirm, then sign in."
            }
        } catch {
            authError = "Network error: \(error.localizedDescription)"
        }
    }
    
    func signIn(email: String, password: String) async {
        isLoading = true
        authError = nil
        defer { isLoading = false }
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode >= 400 {
                if let err = try? JSONDecoder().decode(AuthErrorResponse.self, from: data) {
                    authError = err.displayMessage
                } else {
                    authError = "Login failed (\(statusCode))"
                }
                return
            }
            
            let authResp = try JSONDecoder().decode(AuthResponse.self, from: data)
            handleAuthSuccess(authResp, email: email)
        } catch {
            authError = "Network error: \(error.localizedDescription)"
        }
    }
    
    func signOut() {
        accessToken = nil
        refreshToken = nil
        userId = nil
        userEmail = nil
        isAuthenticated = false
        cancellables.removeAll()
        UserDefaults.standard.removeObject(forKey: "sb_user_email")
    }
    
    private func handleAuthSuccess(_ response: AuthResponse, email: String) {
        accessToken = response.access_token
        refreshToken = response.refresh_token
        userId = response.user.id
        userEmail = email
        UserDefaults.standard.set(email, forKey: "sb_user_email")
        isAuthenticated = true
        
        if let ctx = modelContext {
            startSync(context: ctx)
        }
    }
    
    private func refreshAccessToken() async -> Bool {
        guard let rt = refreshToken else { return false }
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=refresh_token") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": rt])
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode >= 400 {
                signOut()
                return false
            }
            let authResp = try JSONDecoder().decode(AuthResponse.self, from: data)
            accessToken = authResp.access_token
            refreshToken = authResp.refresh_token
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Sync Control
    
    func start(context: ModelContext) {
        self.modelContext = context
        guard isAuthenticated else { return }
        startSync(context: context)
    }
    
    private func startSync(context: ModelContext) {
        self.modelContext = context
        cancellables.removeAll()
        
        // Pull on app foreground
        #if os(macOS)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in await self.pullFromSupabase() }
            }
            .store(in: &cancellables)
        #else
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in await self.pullFromSupabase() }
            }
            .store(in: &cancellables)
        #endif
        
        // Smart polling every 30 seconds (battery-friendly)
        Timer.publish(every: 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in await self.pullFromSupabase() }
            }
            .store(in: &cancellables)
        
        // Initial sync
        Task {
            await pushToSupabase()
            await pullFromSupabase()
        }
    }
    
    /// Fire-and-forget push (call after local saves)
    func push() {
        guard isAuthenticated else { return }
        Task { @MainActor in await pushToSupabase() }
    }
    
    /// Delete items from Supabase (call when hard-deleting locally)
    func deleteRemote(table: String, ids: [String]) {
        guard isAuthenticated, !ids.isEmpty else { return }
        Task { @MainActor in
            let idList = ids.joined(separator: ",")
            guard let url = URL(string: "\(supabaseURL)/rest/v1/\(table)?id=in.(\(idList))") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            _ = await authenticatedRequest(request)
        }
    }
    
    // MARK: - Push to Supabase
    
    private func pushToSupabase() async {
        guard !isSyncing, isAuthenticated, let context = modelContext, let uid = userId else { return }
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
                user_id: uid,
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
                user_id: uid,
                updated_at: now
            )
        }
        
        if !habitDTOs.isEmpty {
            await upsert(table: "habits", items: habitDTOs)
        }
    }
    
    // MARK: - Pull from Supabase
    
    private func pullFromSupabase() async {
        guard !isSyncing, isAuthenticated, let context = modelContext else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        // Pull tasks (RLS filters by user_id automatically)
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
    
    // MARK: - HTTP Helpers (with auto-refresh on 401)
    
    private func upsert<T: Encodable>(table: String, items: [T]) async {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/\(table)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONEncoder().encode(items)
        
        guard let (_, response) = await authenticatedRequest(request) else { return }
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
            print("[Supabase] Upsert \(table) failed: HTTP \(httpResp.statusCode)")
        }
    }
    
    private func fetch<T: Decodable>(table: String) async -> [T]? {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/\(table)?select=*") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        guard let (data, response) = await authenticatedRequest(request) else { return nil }
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
            print("[Supabase] Fetch \(table) failed: HTTP \(httpResp.statusCode)")
            return nil
        }
        return try? JSONDecoder().decode([T].self, from: data)
    }
    
    /// Sends a request with auth headers. Automatically retries once on 401 after refreshing tokens.
    private func authenticatedRequest(_ request: URLRequest) async -> (Data, URLResponse)? {
        var req = request
        req.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            
            // If 401, try refreshing token and retry once
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 401 {
                if await refreshAccessToken() {
                    req.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
                    return try? await URLSession.shared.data(for: req)
                }
                return nil
            }
            
            return (data, response)
        } catch {
            print("[Supabase] Request error: \(error)")
            return nil
        }
    }
}
