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
    let deleted_at: String?
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
    @Published var lastError: String? = nil
    @Published var isLoading: Bool = false
    @Published var isSyncing: Bool = false
    @Published var lastSyncedAt: Date? = nil
    
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
    private var isPushing: Bool = false
    private var isPulling: Bool = false
    private var pendingPushRequested: Bool = false
    private var debounceTimer: AnyCancellable?
    
    // MARK: - Date Formatting & Parsing
    
    private static func formatDate(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
    
    private static func parseDate(_ string: String?) -> Date? {
        guard let string = string, !string.isEmpty else { return nil }
        
        let formatters: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                return f
            }()
        ]
        
        for f in formatters {
            if let date = f.date(from: string) {
                return date
            }
        }
        
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        if let date = df.date(from: string) { return date }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        if let date = df.date(from: string) { return date }
        
        return nil
    }
    
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
        UserDefaults.standard.removeObject(forKey: "sb_access_token")
        UserDefaults.standard.removeObject(forKey: "sb_refresh_token")
        UserDefaults.standard.removeObject(forKey: "sb_user_id")
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
        
        // Background poll every 10 seconds
        Timer.publish(every: 10.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in await self.pullFromSupabase() }
            }
            .store(in: &cancellables)
        
        // Initial sync: refresh token if needed, then push + pull
        Task {
            if refreshToken != nil {
                _ = await refreshAccessToken()
            }
            await pushToSupabase()
            await pullFromSupabase()
        }
    }
    
    /// Instant push call (fire and forget)
    func push() {
        guard isAuthenticated else { return }
        debounceTimer?.cancel()
        Task { @MainActor in await pushToSupabase() }
    }
    
    /// Debounced push for rapid typing (pushes 400ms after last keystroke)
    func pushDebounced() {
        guard isAuthenticated else { return }
        debounceTimer?.cancel()
        debounceTimer = Just(())
            .delay(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in await self.pushToSupabase() }
            }
    }
    
    /// Manual sync trigger (Push + Pull)
    @discardableResult
    func triggerManualSync() async -> Bool {
        guard isAuthenticated, let context = modelContext else { return false }
        lastError = nil
        await pushToSupabase()
        await pullFromSupabase()
        lastSyncedAt = Date()
        return true
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
        if isPushing {
            pendingPushRequested = true
            return
        }
        guard isAuthenticated, let context = modelContext, let uid = userId else { return }
        
        isPushing = true
        isSyncing = true
        defer {
            isPushing = false
            isSyncing = isPulling
            if pendingPushRequested {
                pendingPushRequested = false
                Task { @MainActor in await pushToSupabase() }
            }
        }
        
        try? context.save()
        let pushTimestamp = Date()
        let pushDateString = Self.formatDate(pushTimestamp)
        
        // Push tasks
        let taskDescriptor = FetchDescriptor<TaskItem>()
        let tasks = (try? context.fetch(taskDescriptor)) ?? []
        
        let taskDTOs = tasks.map { task -> SupabaseTaskDTO in
            task.updatedAt = pushTimestamp
            return SupabaseTaskDTO(
                id: task.id,
                text: task.text,
                completed: task.completed,
                created_at: Self.formatDate(task.createdAt),
                interval_type: task.intervalType,
                order: task.order,
                deleted_at: task.deletedAt.map { Self.formatDate($0) },
                completed_at: task.completedAt.map { Self.formatDate($0) },
                user_id: uid,
                updated_at: pushDateString
            )
        }
        
        if !taskDTOs.isEmpty {
            await upsert(table: "tasks", items: taskDTOs)
        }
        
        // Push habits
        let habitDescriptor = FetchDescriptor<HabitItem>()
        let habits = (try? context.fetch(habitDescriptor)) ?? []
        
        let habitDTOs = habits.map { habit -> SupabaseHabitDTO in
            habit.updatedAt = pushTimestamp
            return SupabaseHabitDTO(
                id: habit.id,
                text: habit.text,
                frequency: habit.frequency,
                streak: habit.streak,
                last_completed_date: habit.lastCompletedDate.map { Self.formatDate($0) },
                order: habit.order,
                deleted_at: habit.deletedAt.map { Self.formatDate($0) },
                user_id: uid,
                updated_at: pushDateString
            )
        }
        
        if !habitDTOs.isEmpty {
            await upsert(table: "habits", items: habitDTOs)
        }
        
        try? context.save()
        lastSyncedAt = Date()
    }
    
    // MARK: - Pull from Supabase
    
    private func pullFromSupabase() async {
        if isPulling { return }
        guard isAuthenticated, let context = modelContext else { return }
        
        isPulling = true
        isSyncing = true
        defer {
            isPulling = false
            isSyncing = isPushing
        }
        
        var needsFollowupPush = false
        
        // Pull tasks
        if let remoteTasks: [SupabaseTaskDTO] = await fetch(table: "tasks") {
            let descriptor = FetchDescriptor<TaskItem>()
            let existingTasks = (try? context.fetch(descriptor)) ?? []
            let existingDict = Dictionary(uniqueKeysWithValues: existingTasks.map { ($0.id, $0) })
            let remoteTaskIds = Set(remoteTasks.map { $0.id })
            
            // Only prune local tasks that are soft-deleted locally AND no longer exist on remote
            for existing in existingTasks {
                if existing.deletedAt != nil && !remoteTaskIds.contains(existing.id) {
                    context.delete(existing)
                }
            }
            
            for dto in remoteTasks {
                let remoteUpdatedAt = Self.parseDate(dto.updated_at) ?? Date.distantPast
                if let existing = existingDict[dto.id] {
                    // Accept remote if remote is newer, equal, or within 1.5s tolerance
                    if remoteUpdatedAt >= existing.updatedAt.addingTimeInterval(-1.5) {
                        existing.text = dto.text
                        existing.completed = dto.completed
                        existing.intervalType = dto.interval_type
                        existing.order = dto.order
                        existing.createdAt = Self.parseDate(dto.created_at) ?? existing.createdAt
                        existing.deletedAt = Self.parseDate(dto.deleted_at)
                        existing.completedAt = Self.parseDate(dto.completed_at)
                        existing.updatedAt = remoteUpdatedAt
                    } else if existing.updatedAt.timeIntervalSince(remoteUpdatedAt) > 3.0 {
                        // Local was modified significantly after remote
                        needsFollowupPush = true
                    }
                } else {
                    let newTask = TaskItem(text: dto.text, intervalType: dto.interval_type, order: dto.order)
                    newTask.id = dto.id
                    newTask.completed = dto.completed
                    newTask.createdAt = Self.parseDate(dto.created_at) ?? Date()
                    newTask.deletedAt = Self.parseDate(dto.deleted_at)
                    newTask.completedAt = Self.parseDate(dto.completed_at)
                    newTask.updatedAt = remoteUpdatedAt
                    context.insert(newTask)
                }
            }
        }
        
        // Pull habits
        if let remoteHabits: [SupabaseHabitDTO] = await fetch(table: "habits") {
            let descriptor = FetchDescriptor<HabitItem>()
            let existingHabits = (try? context.fetch(descriptor)) ?? []
            let existingDict = Dictionary(uniqueKeysWithValues: existingHabits.map { ($0.id, $0) })
            let remoteHabitIds = Set(remoteHabits.map { $0.id })
            
            // Only prune local habits that are soft-deleted locally AND no longer exist on remote
            for existing in existingHabits {
                if existing.deletedAt != nil && !remoteHabitIds.contains(existing.id) {
                    context.delete(existing)
                }
            }
            
            for dto in remoteHabits {
                let remoteUpdatedAt = Self.parseDate(dto.updated_at) ?? Date.distantPast
                if let existing = existingDict[dto.id] {
                    if remoteUpdatedAt >= existing.updatedAt.addingTimeInterval(-1.5) {
                        existing.text = dto.text
                        existing.frequency = dto.frequency
                        existing.streak = dto.streak
                        existing.lastCompletedDate = Self.parseDate(dto.last_completed_date)
                        existing.order = dto.order
                        existing.deletedAt = Self.parseDate(dto.deleted_at)
                        existing.updatedAt = remoteUpdatedAt
                    } else if existing.updatedAt.timeIntervalSince(remoteUpdatedAt) > 3.0 {
                        needsFollowupPush = true
                    }
                } else {
                    let newHabit = HabitItem(text: dto.text, frequency: dto.frequency, order: dto.order)
                    newHabit.id = dto.id
                    newHabit.streak = dto.streak
                    newHabit.lastCompletedDate = Self.parseDate(dto.last_completed_date)
                    newHabit.deletedAt = Self.parseDate(dto.deleted_at)
                    newHabit.updatedAt = remoteUpdatedAt
                    context.insert(newHabit)
                }
            }
        }
        
        try? context.save()
        lastSyncedAt = Date()
        
        if needsFollowupPush {
            push()
        }
    }
    
    // MARK: - HTTP Helpers (with auto-refresh on 401)
    
    private func upsert<T: Encodable>(table: String, items: [T]) async {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/\(table)?on_conflict=id") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONEncoder().encode(items)
        
        guard let (data, response) = await authenticatedRequest(request) else { return }
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            let msg = "Upsert \(table) error (HTTP \(httpResp.statusCode)): \(body)"
            print("[Supabase] \(msg)")
            self.lastError = msg
        }
    }
    
    private func fetch<T: Decodable>(table: String) async -> [T]? {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/\(table)?select=*") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        guard let (data, response) = await authenticatedRequest(request) else { return nil }
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            let msg = "Fetch \(table) error (HTTP \(httpResp.statusCode)): \(body)"
            print("[Supabase] \(msg)")
            self.lastError = msg
            return nil
        }
        
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            print("[Supabase] Decode \(table) error: \(error)")
            self.lastError = "Decode \(table) error: \(error.localizedDescription)"
            return nil
        }
    }
    
    /// Sends a request with auth headers. Automatically retries once on 401 after refreshing tokens.
    private func authenticatedRequest(_ request: URLRequest) async -> (Data, URLResponse)? {
        var req = request
        req.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            
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
            self.lastError = "Network error: \(error.localizedDescription)"
            return nil
        }
    }
}
