import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - Notifications

extension Notification.Name {
    static let syncPullDidComplete = Notification.Name("syncPullDidComplete")
}

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
    let error_code: String?
    let msg: String?
    let message: String?
    let error_description: String?
    
    var displayMessage: String {
        msg ?? message ?? error_description ?? error ?? "Unknown error"
    }
    
    /// True when the server explicitly rejected the credentials rather than failing to answer.
    var isInvalidGrant: Bool {
        let fields = [error, error_code, message, error_description, msg].compactMap { $0?.lowercased() }
        return fields.contains { $0.contains("invalid_grant") || $0.contains("refresh token") || $0.contains("invalid token") }
    }
}

// MARK: - Supabase DTOs (for decoding)

// Every column is decoded optionally: one malformed or NULL field must never be able to
// take down the sync of an entire table.

struct SupabaseTaskDTO: Decodable {
    let id: String
    let text: String?
    let completed: Bool?
    let created_at: String?
    let interval_type: String?
    let order: Int?
    let deleted_at: String?
    let completed_at: String?
    let habit_id: String?
    let user_id: String?
    let updated_at: String?
}

struct SupabaseHabitDTO: Decodable {
    let id: String
    let text: String?
    let frequency: String?
    let streak: Int?
    let last_completed_date: String?
    let order: Int?
    let deleted_at: String?
    let user_id: String?
    let updated_at: String?
}

struct SupabaseScratchpadListDTO: Decodable {
    let id: String
    let title: String?
    let order: Int?
    let created_at: String?
    let deleted_at: String?
    let user_id: String?
    let updated_at: String?
}

struct SupabaseScratchpadItemDTO: Decodable {
    let id: String
    let list_id: String?
    let text: String?
    let completed: Bool?
    let order: Int?
    let created_at: String?
    let deleted_at: String?
    let completed_at: String?
    let user_id: String?
    let updated_at: String?
}

struct ScratchpadMemberDTO: Codable, Identifiable {
    let id: String
    let list_id: String
    let owner_id: String
    let owner_email: String?
    let invited_email: String
    let member_user_id: String?
    let role: String?
    let created_at: String?
}

/// Wrapper that turns an undecodable row into `nil` instead of failing the whole array.
private struct FailableRow<T: Decodable>: Decodable {
    let value: T?
    
    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}

// MARK: - Supabase Sync Manager

@MainActor
class SupabaseSyncManager: ObservableObject {
    static let shared = SupabaseSyncManager()
    
    private let supabaseURL = "https://mrqgudqemlgdxnrqxqtk.supabase.co"
    private let supabaseKey = "sb_publishable_KV6DvqpKbl6wmMZvcwPczw_ID2hOShH"
    
    private enum StoreKey {
        static let accessToken = "sb_access_token"
        static let refreshToken = "sb_refresh_token"
        static let userId = "sb_user_id"
        static let userEmail = "sb_user_email"
        static let tokenExpiry = "sb_token_expiry"
        static let serverTimeOffset = "sb_server_time_offset"
        static let tombstones = "sb_tombstones"
        static let binReconciled = "sb_bin_reconciled"
    }
    
    private let pollInterval: TimeInterval = 10
    private let debounceDelay: TimeInterval = 0.6
    /// Server rows are read in pages: PostgREST caps an unbounded select at 1000 rows.
    private let pageSize = 500
    private let upsertBatchSize = 200
    private let deleteBatchSize = 40
    private let maxPages = 400
    private let tokenRefreshLeeway: TimeInterval = 120
    
    @Published var isAuthenticated: Bool = false
    @Published var userEmail: String? = nil
    @Published var authError: String? = nil
    @Published var lastError: String? = nil
    @Published var isLoading: Bool = false
    @Published var isSyncing: Bool = false
    @Published var lastSyncedAt: Date? = nil
    
    var isConfigured: Bool { isAuthenticated }
    
    private var accessToken: String? {
        didSet { UserDefaults.standard.set(accessToken, forKey: StoreKey.accessToken) }
    }
    private var refreshToken: String? {
        didSet { UserDefaults.standard.set(refreshToken, forKey: StoreKey.refreshToken) }
    }
    private(set) var userId: String? {
        didSet { UserDefaults.standard.set(userId, forKey: StoreKey.userId) }
    }
    private var accessTokenExpiry: Date? {
        didSet { UserDefaults.standard.set(accessTokenExpiry?.timeIntervalSince1970, forKey: StoreKey.tokenExpiry) }
    }
    
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var debounceTimer: AnyCancellable?
    private var isSyncLoopRunning = false
    
    private var isPushing = false
    private var isPulling = false
    private var pendingPushRequested = false
    private var pendingPullRequested = false
    
    private var refreshTask: Task<Bool, Never>?
    private var pendingLocalPurge = false
    
    private var clock = ServerClock()
    private var ledger = TombstoneLedger()
    private var backoff = SyncBackoff()
    /// Off for test instances, which must not write to the real defaults.
    private var persistsLedger = true
    
    /// Databases created before the habit link feature have no `habit_id` column. The column
    /// is dropped from the payload if the server rejects it, so an older schema degrades to
    /// device-local habit links instead of breaking every task push.
    private var tasksSupportHabitId = true
    
    /// Rows missing from the previous server snapshot. A row must be absent twice in a row
    /// before it is deleted locally, so a single incomplete snapshot cannot destroy data.
    private var missingTaskIds = Set<String>()
    private var missingHabitIds = Set<String>()
    
    /// Builds before per-row sync tracking hard-deleted rows locally without recording a
    /// tombstone, leaving orphaned soft-deleted rows on the server. They are cleared out once,
    /// on the first successful pull after the upgrade, and only for stores that already hold
    /// data — on a fresh install those same rows are the user's real recycle bin.
    private var legacyBinPurgeArmed = false
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    private init() {
        let defaults = UserDefaults.standard
        accessToken = defaults.string(forKey: StoreKey.accessToken)
        refreshToken = defaults.string(forKey: StoreKey.refreshToken)
        userId = defaults.string(forKey: StoreKey.userId)
        userEmail = defaults.string(forKey: StoreKey.userEmail)
        isAuthenticated = accessToken != nil && userId != nil
        clock.offset = defaults.double(forKey: StoreKey.serverTimeOffset)
        if let expiry = defaults.object(forKey: StoreKey.tokenExpiry) as? Double {
            accessTokenExpiry = Date(timeIntervalSince1970: expiry)
        }
        ledger = TombstoneLedger.decode(from: defaults.data(forKey: StoreKey.tombstones))
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
            let (data, response) = try await session.data(for: request)
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
            let (data, response) = try await session.data(for: request)
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
    
    func resetPassword(email: String) async -> (success: Bool, error: String?) {
        isLoading = true
        authError = nil
        defer { isLoading = false }
        
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
            return (false, "Invalid email address".localized)
        }
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/recover") else {
            return (false, "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": trimmedEmail])
        
        do {
            let (data, response) = try await session.data(for: request)
            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode >= 400 {
                if let err = try? JSONDecoder().decode(AuthErrorResponse.self, from: data) {
                    return (false, err.displayMessage)
                } else {
                    return (false, "Password recovery failed (\(statusCode))")
                }
            }
            return (true, nil)
        } catch {
            return (false, "Network error: \(error.localizedDescription)")
        }
    }
    
    func signOut() {
        if let ctx = modelContext {
            purgeLocalStore(context: ctx)
        } else {
            pendingLocalPurge = true
        }
        accessToken = nil
        refreshToken = nil
        accessTokenExpiry = nil
        userId = nil
        userEmail = nil
        isAuthenticated = false
        isSyncLoopRunning = false
        cancellables.removeAll()
        debounceTimer?.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        missingTaskIds.removeAll()
        missingHabitIds.removeAll()
        ledger.removeAll()
        persistLedger()
        UserDefaults.standard.removeObject(forKey: StoreKey.userEmail)
        UserDefaults.standard.removeObject(forKey: StoreKey.accessToken)
        UserDefaults.standard.removeObject(forKey: StoreKey.refreshToken)
        UserDefaults.standard.removeObject(forKey: StoreKey.userId)
        UserDefaults.standard.removeObject(forKey: StoreKey.tokenExpiry)
    }
    
    func deleteAccount() async {
        guard let uid = userId, let token = accessToken else {
            signOut()
            return
        }
        let tables = ["tasks", "habits", "scratchpad_items", "scratchpad_lists"]
        for table in tables {
            guard let url = URL(string: "\(supabaseURL)/rest/v1/\(table)?user_id=eq.\(uid)") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue(supabaseKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
        }
        signOut()
    }

    
    private func handleAuthSuccess(_ response: AuthResponse, email: String) {
        // Signing in must wipe any previously cached account data to ensure privacy
        if let ctx = modelContext {
            purgeLocalStore(context: ctx)
        } else {
            pendingLocalPurge = true
        }
        ledger.removeAll()
        persistLedger()
        missingTaskIds.removeAll()
        missingHabitIds.removeAll()
        
        applyTokens(response)
        userId = response.user.id
        userEmail = email
        UserDefaults.standard.set(email, forKey: StoreKey.userEmail)
        isAuthenticated = true
        
        if let ctx = modelContext {
            startSync(context: ctx)
            Task { @MainActor in
                _ = await self.runSyncCycle(force: true)
            }
        }
    }
    
    private func applyTokens(_ response: AuthResponse) {
        accessToken = response.access_token
        refreshToken = response.refresh_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(response.expires_in))
    }
    
    /// Refreshes the access token before it expires. Concurrent callers share one request:
    /// Supabase rotates refresh tokens, so parallel refreshes would invalidate each other.
    @discardableResult
    private func refreshAccessToken() async -> Bool {
        if let inFlight = refreshTask {
            return await inFlight.value
        }
        guard let currentRefreshToken = refreshToken else { return false }
        
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self = self else { return false }
            return await self.performTokenRefresh(using: currentRefreshToken)
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }
    
    private func performTokenRefresh(using currentRefreshToken: String) async -> Bool {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=refresh_token") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": currentRefreshToken])
        
        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            if statusCode >= 400 {
                let err = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
                // Only a rejected token ends the session. A server or transport failure is
                // transient and must never sign the user out.
                if statusCode == 400 || statusCode == 401, err?.isInvalidGrant ?? true {
                    signOut()
                } else {
                    lastError = "Auth refresh failed (HTTP \(statusCode))"
                }
                return false
            }
            
            let authResp = try JSONDecoder().decode(AuthResponse.self, from: data)
            applyTokens(authResp)
            return true
        } catch {
            return false
        }
    }
    
    private func ensureFreshToken() async {
        guard isAuthenticated, let expiry = accessTokenExpiry else { return }
        if expiry.timeIntervalSinceNow < tokenRefreshLeeway {
            await refreshAccessToken()
        }
    }
    
    // MARK: - Sync Control
    
    func start(context: ModelContext) {
        self.modelContext = context
        
        if pendingLocalPurge {
            purgeLocalStore(context: context)
            pendingLocalPurge = false
        }
        
        guard isAuthenticated, !isSyncLoopRunning else { return }
        startSync(context: context)
    }
    
    private func startSync(context: ModelContext) {
        self.modelContext = context
        cancellables.removeAll()
        isSyncLoopRunning = true
        armLegacyBinPurgeIfNeeded(context: context)
        
        // Pull on app foreground, and flush pending edits before the app is suspended.
        #if os(macOS)
        let activeNotification = NSApplication.didBecomeActiveNotification
        let inactiveNotification = NSApplication.willResignActiveNotification
        #else
        let activeNotification = UIApplication.didBecomeActiveNotification
        let inactiveNotification = UIApplication.didEnterBackgroundNotification
        #endif
        
        NotificationCenter.default.publisher(for: activeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in _ = await self?.runSyncCycle(force: true) }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: inactiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in _ = await self?.pushToSupabase() }
            }
            .store(in: &cancellables)
        
        // Background poll — always push before pull to prevent overwriting local edits.
        Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in _ = await self?.runSyncCycle(force: false) }
            }
            .store(in: &cancellables)
        
        // Initial sync
        Task { @MainActor in
            await ensureFreshToken()
            _ = await runSyncCycle(force: true)
        }
    }
    
    /// Push then pull. Scheduled cycles respect the retry backoff; user- and edit-triggered
    /// cycles are always attempted.
    @discardableResult
    private func runSyncCycle(force: Bool) async -> Bool {
        guard isAuthenticated else { return false }
        if !force && !backoff.allowsAttempt() { return false }
        
        let pushed = await pushToSupabase()
        let pulled = await pullFromSupabase()
        return pushed && pulled
    }
    
    /// Instant push call (fire and forget)
    func push() {
        guard isAuthenticated else { return }
        debounceTimer?.cancel()
        Task { @MainActor in _ = await pushToSupabase() }
    }
    
    /// Debounced push for rapid typing (pushes shortly after the last keystroke)
    func pushDebounced() {
        guard isAuthenticated else { return }
        debounceTimer?.cancel()
        debounceTimer = Just(())
            .delay(for: .seconds(debounceDelay), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in _ = await self?.pushToSupabase() }
            }
    }
    
    /// Manual sync trigger (Push + Pull)
    @discardableResult
    func triggerManualSync() async -> Bool {
        guard isAuthenticated, modelContext != nil else { return false }
        return await runSyncCycle(force: true)
    }
    
    /// Permanently removes rows from the server. The ids are tombstoned first, so the delete
    /// is retried until the server confirms it and an in-flight pull can never bring them back.
    /// Call this *before* deleting the rows from the local store.
    func deleteRemote(table: String, ids: [String]) {
        guard !ids.isEmpty else { return }
        ledger.add(table: table, ids: ids)
        persistLedger()
        guard isAuthenticated else { return }
        Task { @MainActor in
            await ensureFreshToken()
            _ = await flushTombstones()
        }
    }
    
    // MARK: - Push to Supabase
    
    @discardableResult
    private func pushToSupabase() async -> Bool {
        if isPushing {
            pendingPushRequested = true
            return true
        }
        guard isAuthenticated, let context = modelContext, let uid = userId else { return false }
        
        isPushing = true
        isSyncing = true
        defer {
            isPushing = false
            isSyncing = isPulling
            if pendingPushRequested {
                pendingPushRequested = false
                Task { @MainActor in _ = await pushToSupabase() }
            }
        }
        
        await ensureFreshToken()
        persist(context)
        
        var succeeded = await flushTombstones()
        
        // Tasks
        let tasks = pushableTasks(context: context)
        for chunk in tasks.filter({ needsPush($0) }).chunked(into: upsertBatchSize) {
            // Capture the stamps before awaiting: an edit made while the request is in flight
            // must leave the row dirty so that the edit is published by the next push.
            let stamps = chunk.map { $0.updatedAt }
            let payload = chunk.map { taskPayload($0, uid: uid) }
            guard await upsert(table: SyncTable.tasks, payload: payload) else {
                succeeded = false
                break
            }
            for (index, task) in chunk.enumerated() {
                task.syncedAt = stamps[index]
            }
        }
        
        // Habits
        let habits = pushableHabits(context: context)
        for chunk in habits.filter({ needsPush($0) }).chunked(into: upsertBatchSize) {
            let stamps = chunk.map { $0.updatedAt }
            let payload = chunk.map { habitPayload($0, uid: uid) }
            guard await upsert(table: SyncTable.habits, payload: payload) else {
                succeeded = false
                break
            }
            for (index, habit) in chunk.enumerated() {
                habit.syncedAt = stamps[index]
            }
        }
        
        // Scratchpad Lists
        let scratchpadLists = pushableScratchpadLists(context: context)
        for chunk in scratchpadLists.filter({ needsPush($0) }).chunked(into: upsertBatchSize) {
            let stamps = chunk.map { $0.updatedAt }
            let payload = chunk.map { scratchpadListPayload($0, uid: uid) }
            if await upsert(table: SyncTable.scratchpadLists, payload: payload) {
                for (index, item) in chunk.enumerated() {
                    item.syncedAt = stamps[index]
                }
            }
        }
        
        // Scratchpad Items
        let scratchpadItems = pushableScratchpadItems(context: context)
        for chunk in scratchpadItems.filter({ needsPush($0) }).chunked(into: upsertBatchSize) {
            let stamps = chunk.map { $0.updatedAt }
            let payload = chunk.map { scratchpadItemPayload($0, uid: uid) }
            if await upsert(table: SyncTable.scratchpadItems, payload: payload) {
                for (index, item) in chunk.enumerated() {
                    item.syncedAt = stamps[index]
                }
            }
        }
        
        persist(context)
        
        if succeeded {
            noteSyncSuccess()
        } else {
            backoff.recordFailure()
        }
        return succeeded
    }
    
    /// Local housekeeping performed before every push: duplicate ids are collapsed, abandoned
    /// blank rows are removed, and blank editing placeholders are held back from the server.
    private func pushableTasks(context: ModelContext) -> [TaskItem] {
        let byId = deduplicatedTasks(context: context)
        var pushable: [TaskItem] = []
        
        for task in byId.values {
            if ledger.contains(table: SyncTable.tasks, id: task.id) {
                // The row was destroyed for good; a copy reappearing locally is a stale echo.
                context.delete(task)
                continue
            }
            
            let isBlank = task.text.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && task.deletedAt != nil {
                if task.syncedAt != nil {
                    deleteRemote(table: SyncTable.tasks, ids: [task.id])
                }
                context.delete(task)
                continue
            }
            // A blank row is an editing placeholder, not data.
            if isBlank { continue }
            
            pushable.append(task)
        }
        return pushable
    }
    
    private func pushableHabits(context: ModelContext) -> [HabitItem] {
        let byId = deduplicatedHabits(context: context)
        var pushable: [HabitItem] = []
        
        for habit in byId.values {
            if ledger.contains(table: SyncTable.habits, id: habit.id) {
                context.delete(habit)
                continue
            }
            if habit.text.trimmingCharacters(in: .whitespaces).isEmpty {
                if habit.syncedAt != nil {
                    deleteRemote(table: SyncTable.habits, ids: [habit.id])
                }
                context.delete(habit)
                continue
            }
            pushable.append(habit)
        }
        return pushable
    }
    
    private func pushableScratchpadLists(context: ModelContext) -> [ScratchpadList] {
        guard let all = try? context.fetch(FetchDescriptor<ScratchpadList>()) else { return [] }
        return all.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty || $0.deletedAt != nil }
    }
    
    private func pushableScratchpadItems(context: ModelContext) -> [ScratchpadItem] {
        guard let all = try? context.fetch(FetchDescriptor<ScratchpadItem>()) else { return [] }
        return all.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty || $0.deletedAt != nil }
    }
    
    // Explicit dictionary payloads guarantee key symmetry across the array (PostgREST PGRST102).
    private func taskPayload(_ task: TaskItem, uid: String) -> [String: Any] {
        var payload: [String: Any] = [
            "id": task.id,
            "text": task.text,
            "completed": task.completed,
            "created_at": SyncTimestamp.format(task.createdAt),
            "interval_type": task.intervalType,
            "order": task.order,
            "deleted_at": task.deletedAt.map { SyncTimestamp.format($0) } ?? NSNull(),
            "completed_at": task.completedAt.map { SyncTimestamp.format($0) } ?? NSNull(),
            "user_id": uid,
            "updated_at": SyncTimestamp.format(clock.toServer(task.updatedAt))
        ]
        if tasksSupportHabitId {
            payload["habit_id"] = task.habitId ?? NSNull()
        }
        return payload
    }
    
    private func habitPayload(_ habit: HabitItem, uid: String) -> [String: Any] {
        [
            "id": habit.id,
            "text": habit.text,
            "frequency": habit.frequency,
            "streak": habit.streak,
            "last_completed_date": habit.lastCompletedDate.map { SyncTimestamp.format($0) } ?? NSNull(),
            "order": habit.order,
            "deleted_at": habit.deletedAt.map { SyncTimestamp.format($0) } ?? NSNull(),
            "user_id": uid,
            "updated_at": SyncTimestamp.format(clock.toServer(habit.updatedAt))
        ]
    }
    
    private func scratchpadListPayload(_ list: ScratchpadList, uid: String) -> [String: Any] {
        [
            "id": list.id,
            "title": list.title,
            "order": list.order,
            "created_at": SyncTimestamp.format(list.createdAt),
            "deleted_at": list.deletedAt.map { SyncTimestamp.format($0) } ?? NSNull(),
            "user_id": uid,
            "updated_at": SyncTimestamp.format(clock.toServer(list.updatedAt))
        ]
    }
    
    private func scratchpadItemPayload(_ item: ScratchpadItem, uid: String) -> [String: Any] {
        [
            "id": item.id,
            "list_id": item.listId,
            "text": item.text,
            "completed": item.completed,
            "order": item.order,
            "created_at": SyncTimestamp.format(item.createdAt),
            "deleted_at": item.deletedAt.map { SyncTimestamp.format($0) } ?? NSNull(),
            "completed_at": item.completedAt.map { SyncTimestamp.format($0) } ?? NSNull(),
            "user_id": uid,
            "updated_at": SyncTimestamp.format(clock.toServer(item.updatedAt))
        ]
    }
    
    private func needsPush(_ item: ScratchpadList) -> Bool {
        guard let synced = item.syncedAt else { return true }
        return item.updatedAt > synced
    }
    
    private func needsPush(_ item: ScratchpadItem) -> Bool {
        guard let synced = item.syncedAt else { return true }
        return item.updatedAt > synced
    }
    
    // MARK: - Pull from Supabase
    
    @discardableResult
    private func pullFromSupabase() async -> Bool {
        if isPulling {
            pendingPullRequested = true
            return true
        }
        guard isAuthenticated, let context = modelContext, let uid = userId else { return false }
        
        isPulling = true
        isSyncing = true
        defer {
            isPulling = false
            isSyncing = isPushing
            if pendingPullRequested {
                pendingPullRequested = false
                Task { @MainActor in _ = await pullFromSupabase() }
            }
        }
        
        await ensureFreshToken()
        
        // Both snapshots must be complete before anything is merged: a partial snapshot must
        // never be mistaken for rows having been deleted elsewhere.
        guard let remoteTasks: [SupabaseTaskDTO] = await fetchAll(table: SyncTable.tasks, uid: uid),
              let remoteHabits: [SupabaseHabitDTO] = await fetchAll(table: SyncTable.habits, uid: uid) else {
            backoff.recordFailure()
            return false
        }
        
        var needsFollowupPush = mergeRemoteTasks(remoteTasks, context: context, uid: uid)
        if mergeRemoteHabits(remoteHabits, context: context, uid: uid) {
            needsFollowupPush = true
        }
        
        if let remoteScratchpadLists: [SupabaseScratchpadListDTO] = await fetchAll(table: SyncTable.scratchpadLists, uid: uid, filterByUserId: false) {
            if mergeRemoteScratchpadLists(remoteScratchpadLists, context: context, uid: uid) {
                needsFollowupPush = true
            }
        }
        
        if let remoteScratchpadItems: [SupabaseScratchpadItemDTO] = await fetchAll(table: SyncTable.scratchpadItems, uid: uid, filterByUserId: false) {
            if mergeRemoteScratchpadItems(remoteScratchpadItems, context: context, uid: uid) {
                needsFollowupPush = true
            }
        }
        
        persist(context)
        completeLegacyBinPurge()
        noteSyncSuccess()
        NotificationCenter.default.post(name: .syncPullDidComplete, object: nil)
        
        if needsFollowupPush {
            push()
        }
        return true
    }
    
    private func mergeRemoteTasks(_ dtos: [SupabaseTaskDTO], context: ModelContext, uid: String) -> Bool {
        var needsFollowupPush = false
        var localById = deduplicatedTasks(context: context)
        var orphanRemoteIds: [String] = []
        var remoteIds = Set<String>()
        
        for dto in dtos {
            if let owner = dto.user_id, owner != uid { continue }
            remoteIds.insert(dto.id)
            
            if ledger.contains(table: SyncTable.tasks, id: dto.id) {
                if let stale = localById.removeValue(forKey: dto.id) { context.delete(stale) }
                continue
            }
            
            let text = (dto.text ?? "").trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                // Blank rows never belong on the server; drop the copy unless it is a live
                // placeholder on this device.
                if localById[dto.id] == nil { orphanRemoteIds.append(dto.id) }
                continue
            }
            
            let remoteStamp = SyncTimestamp.parse(dto.updated_at).map { clock.toLocal($0) }
            
            if let existing = localById[dto.id] {
                switch MergePolicy.resolve(remoteUpdatedAt: remoteStamp,
                                           localUpdatedAt: existing.updatedAt,
                                           localSyncedAt: existing.syncedAt) {
                case .adoptRemote(let stamp):
                    assign(text, to: existing, \.text)
                    assign(dto.completed ?? existing.completed, to: existing, \.completed)
                    assign(dto.interval_type ?? existing.intervalType, to: existing, \.intervalType)
                    assign(dto.order ?? existing.order, to: existing, \.order)
                    assign(SyncTimestamp.parse(dto.created_at) ?? existing.createdAt, to: existing, \.createdAt)
                    assign(SyncTimestamp.parse(dto.deleted_at), to: existing, \.deletedAt)
                    assign(SyncTimestamp.parse(dto.completed_at), to: existing, \.completedAt)
                    // A link is only ever adopted, never cleared: a database without the
                    // habit_id column reports nil for every row and would otherwise wipe the
                    // links held on this device.
                    if let remoteHabitId = dto.habit_id {
                        assign(Optional(remoteHabitId), to: existing, \.habitId)
                    }
                    // The row now *is* the server's version, timestamp included, so the next
                    // pull finds nothing left to do.
                    assign(stamp, to: existing, \.updatedAt)
                    assign(Optional(stamp), to: existing, \.syncedAt)
                case .republishLocal:
                    // Either the server holds an older copy or its timestamp is unreadable.
                    // Marking the row unpublished makes the next push send it.
                    existing.syncedAt = nil
                    needsFollowupPush = true
                case .keepLocalAndPush:
                    needsFollowupPush = true
                case .keepLocal:
                    break
                }
            } else {
                if dto.deleted_at != nil && legacyBinPurgeArmed {
                    orphanRemoteIds.append(dto.id)
                    continue
                }
                
                let task = TaskItem(text: text, intervalType: dto.interval_type ?? "1 Day", order: dto.order ?? 0)
                task.id = dto.id
                task.completed = dto.completed ?? false
                task.createdAt = SyncTimestamp.parse(dto.created_at) ?? Date()
                task.deletedAt = SyncTimestamp.parse(dto.deleted_at)
                task.completedAt = SyncTimestamp.parse(dto.completed_at)
                task.habitId = dto.habit_id
                task.updatedAt = remoteStamp ?? Date()
                task.syncedAt = remoteStamp
                context.insert(task)
                localById[dto.id] = task
                if remoteStamp == nil { needsFollowupPush = true }
            }
        }
        
        missingTaskIds = pruneVanished(
            localById.filter { !remoteIds.contains($0.key) && !needsPush($0.value) },
            previouslyMissing: missingTaskIds,
            context: context
        )
        
        if !orphanRemoteIds.isEmpty {
            deleteRemote(table: SyncTable.tasks, ids: orphanRemoteIds)
        }
        return needsFollowupPush
    }
    
    private func mergeRemoteHabits(_ dtos: [SupabaseHabitDTO], context: ModelContext, uid: String) -> Bool {
        var needsFollowupPush = false
        var localById = deduplicatedHabits(context: context)
        var orphanRemoteIds: [String] = []
        var remoteIds = Set<String>()
        
        for dto in dtos {
            if let owner = dto.user_id, owner != uid { continue }
            remoteIds.insert(dto.id)
            
            if ledger.contains(table: SyncTable.habits, id: dto.id) {
                if let stale = localById.removeValue(forKey: dto.id) { context.delete(stale) }
                continue
            }
            
            let text = (dto.text ?? "").trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                if localById[dto.id] == nil { orphanRemoteIds.append(dto.id) }
                continue
            }
            
            let remoteStamp = SyncTimestamp.parse(dto.updated_at).map { clock.toLocal($0) }
            
            if let existing = localById[dto.id] {
                switch MergePolicy.resolve(remoteUpdatedAt: remoteStamp,
                                           localUpdatedAt: existing.updatedAt,
                                           localSyncedAt: existing.syncedAt) {
                case .adoptRemote(let stamp):
                    assign(text, to: existing, \.text)
                    assign(dto.frequency ?? existing.frequency, to: existing, \.frequency)
                    assign(dto.streak ?? existing.streak, to: existing, \.streak)
                    assign(SyncTimestamp.parse(dto.last_completed_date), to: existing, \.lastCompletedDate)
                    assign(dto.order ?? existing.order, to: existing, \.order)
                    assign(SyncTimestamp.parse(dto.deleted_at), to: existing, \.deletedAt)
                    assign(stamp, to: existing, \.updatedAt)
                    assign(Optional(stamp), to: existing, \.syncedAt)
                case .republishLocal:
                    existing.syncedAt = nil
                    needsFollowupPush = true
                case .keepLocalAndPush:
                    needsFollowupPush = true
                case .keepLocal:
                    break
                }
            } else {
                if dto.deleted_at != nil && legacyBinPurgeArmed {
                    orphanRemoteIds.append(dto.id)
                    continue
                }
                
                let habit = HabitItem(text: text, frequency: dto.frequency ?? "Daily", order: dto.order ?? 0)
                habit.id = dto.id
                habit.streak = dto.streak ?? 0
                habit.lastCompletedDate = SyncTimestamp.parse(dto.last_completed_date)
                habit.deletedAt = SyncTimestamp.parse(dto.deleted_at)
                habit.updatedAt = remoteStamp ?? Date()
                habit.syncedAt = remoteStamp
                context.insert(habit)
                localById[dto.id] = habit
                if remoteStamp == nil { needsFollowupPush = true }
            }
        }
        
        missingHabitIds = pruneVanished(
            localById.filter { !remoteIds.contains($0.key) && !needsPush($0.value) },
            previouslyMissing: missingHabitIds,
            context: context
        )
        
        if !orphanRemoteIds.isEmpty {
            deleteRemote(table: SyncTable.habits, ids: orphanRemoteIds)
        }
        return needsFollowupPush
    }
    
    private func mergeRemoteScratchpadLists(_ dtos: [SupabaseScratchpadListDTO], context: ModelContext, uid: String) -> Bool {
        var needsFollowupPush = false
        guard let all = try? context.fetch(FetchDescriptor<ScratchpadList>()) else { return false }
        var localById = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        
        for dto in dtos {
            let title = (dto.title ?? "").trimmingCharacters(in: .whitespaces)
            let remoteStamp = SyncTimestamp.parse(dto.updated_at).map { clock.toLocal($0) }
            
            if let existing = localById[dto.id] {
                if existing.ownerId != dto.user_id {
                    existing.ownerId = dto.user_id
                }
                switch MergePolicy.resolve(remoteUpdatedAt: remoteStamp, localUpdatedAt: existing.updatedAt, localSyncedAt: existing.syncedAt) {
                case .adoptRemote(let stamp):
                    assign(title, to: existing, \.title)
                    assign(dto.order ?? existing.order, to: existing, \.order)
                    assign(dto.user_id, to: existing, \.ownerId)
                    assign(SyncTimestamp.parse(dto.created_at) ?? existing.createdAt, to: existing, \.createdAt)
                    assign(SyncTimestamp.parse(dto.deleted_at), to: existing, \.deletedAt)
                    assign(stamp, to: existing, \.updatedAt)
                    assign(Optional(stamp), to: existing, \.syncedAt)
                case .republishLocal, .keepLocalAndPush:
                    needsFollowupPush = true
                case .keepLocal:
                    break
                }
            } else {
                let list = ScratchpadList(title: title, order: dto.order ?? 0, ownerId: dto.user_id)
                list.id = dto.id
                list.createdAt = SyncTimestamp.parse(dto.created_at) ?? Date()
                list.deletedAt = SyncTimestamp.parse(dto.deleted_at)
                list.updatedAt = remoteStamp ?? Date()
                list.syncedAt = remoteStamp
                context.insert(list)
                localById[dto.id] = list
                if remoteStamp == nil { needsFollowupPush = true }
            }
        }
        return needsFollowupPush
    }
    
    private func mergeRemoteScratchpadItems(_ dtos: [SupabaseScratchpadItemDTO], context: ModelContext, uid: String) -> Bool {
        var needsFollowupPush = false
        guard let all = try? context.fetch(FetchDescriptor<ScratchpadItem>()) else { return false }
        var localById = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        
        for dto in dtos {
            let text = (dto.text ?? "").trimmingCharacters(in: .whitespaces)
            let remoteStamp = SyncTimestamp.parse(dto.updated_at).map { clock.toLocal($0) }
            
            if let existing = localById[dto.id] {
                switch MergePolicy.resolve(remoteUpdatedAt: remoteStamp, localUpdatedAt: existing.updatedAt, localSyncedAt: existing.syncedAt) {
                case .adoptRemote(let stamp):
                    assign(dto.list_id ?? existing.listId, to: existing, \.listId)
                    assign(text, to: existing, \.text)
                    assign(dto.completed ?? existing.completed, to: existing, \.completed)
                    assign(dto.order ?? existing.order, to: existing, \.order)
                    assign(SyncTimestamp.parse(dto.created_at) ?? existing.createdAt, to: existing, \.createdAt)
                    assign(SyncTimestamp.parse(dto.deleted_at), to: existing, \.deletedAt)
                    assign(SyncTimestamp.parse(dto.completed_at), to: existing, \.completedAt)
                    assign(stamp, to: existing, \.updatedAt)
                    assign(Optional(stamp), to: existing, \.syncedAt)
                case .republishLocal, .keepLocalAndPush:
                    needsFollowupPush = true
                case .keepLocal:
                    break
                }
            } else {
                let item = ScratchpadItem(listId: dto.list_id ?? "", text: text, order: dto.order ?? 0)
                item.id = dto.id
                item.completed = dto.completed ?? false
                item.createdAt = SyncTimestamp.parse(dto.created_at) ?? Date()
                item.deletedAt = SyncTimestamp.parse(dto.deleted_at)
                item.completedAt = SyncTimestamp.parse(dto.completed_at)
                item.updatedAt = remoteStamp ?? Date()
                item.syncedAt = remoteStamp
                context.insert(item)
                localById[dto.id] = item
                if remoteStamp == nil { needsFollowupPush = true }
            }
        }
        return needsFollowupPush
    }
    
    /// A row that was in sync and has disappeared from a complete server snapshot was
    /// hard-deleted on another device. Deleting it locally is deferred until it has been
    /// absent from two consecutive snapshots.
    private func pruneVanished<T: PersistentModel>(_ candidates: [String: T], previouslyMissing: Set<String>, context: ModelContext) -> Set<String> {
        var stillMissing = Set<String>()
        for (id, model) in candidates {
            if previouslyMissing.contains(id) {
                context.delete(model)
            } else {
                stillMissing.insert(id)
            }
        }
        return stillMissing
    }
    
    // MARK: - Local Store Helpers
    
    /// SwiftData does not enforce uniqueness on `id`, so duplicates are collapsed by keeping
    /// the most recently edited row. This also keeps the merge from trapping on duplicate keys.
    private func deduplicatedTasks(context: ModelContext) -> [String: TaskItem] {
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        var byId: [String: TaskItem] = [:]
        for task in all {
            guard let existing = byId[task.id] else {
                byId[task.id] = task
                continue
            }
            if task.updatedAt > existing.updatedAt {
                context.delete(existing)
                byId[task.id] = task
            } else {
                context.delete(task)
            }
        }
        return byId
    }
    
    private func deduplicatedHabits(context: ModelContext) -> [String: HabitItem] {
        let all = (try? context.fetch(FetchDescriptor<HabitItem>())) ?? []
        var byId: [String: HabitItem] = [:]
        for habit in all {
            guard let existing = byId[habit.id] else {
                byId[habit.id] = habit
                continue
            }
            if habit.updatedAt > existing.updatedAt {
                context.delete(existing)
                byId[habit.id] = habit
            } else {
                context.delete(habit)
            }
        }
        return byId
    }
    
    func purgeLocalStore(context: ModelContext) {
        for task in (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [] { context.delete(task) }
        for habit in (try? context.fetch(FetchDescriptor<HabitItem>())) ?? [] { context.delete(habit) }
        for item in (try? context.fetch(FetchDescriptor<ScratchpadItem>())) ?? [] { context.delete(item) }
        for list in (try? context.fetch(FetchDescriptor<ScratchpadList>())) ?? [] { context.delete(list) }
        persist(context)
    }
    
    private func persist(_ context: ModelContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("[Supabase] Local save error: \(error)")
            lastError = "Local save error: \(error.localizedDescription)"
        }
    }
    
    private func needsPush(_ task: TaskItem) -> Bool {
        MergePolicy.needsPush(updatedAt: task.updatedAt, syncedAt: task.syncedAt)
    }
    
    private func needsPush(_ habit: HabitItem) -> Bool {
        MergePolicy.needsPush(updatedAt: habit.updatedAt, syncedAt: habit.syncedAt)
    }
    
    @discardableResult
    private func assign<Root: AnyObject, Value: Equatable>(_ value: Value, to root: Root, _ keyPath: ReferenceWritableKeyPath<Root, Value>) -> Bool {
        guard root[keyPath: keyPath] != value else { return false }
        root[keyPath: keyPath] = value
        return true
    }
    
    private func armLegacyBinPurgeIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: StoreKey.binReconciled) else { return }
        var descriptor = FetchDescriptor<TaskItem>()
        descriptor.fetchLimit = 1
        let hasLocalData = ((try? context.fetch(descriptor)) ?? []).isEmpty == false
        if hasLocalData {
            legacyBinPurgeArmed = true
        } else {
            UserDefaults.standard.set(true, forKey: StoreKey.binReconciled)
        }
    }
    
    private func completeLegacyBinPurge() {
        guard legacyBinPurgeArmed else { return }
        legacyBinPurgeArmed = false
        UserDefaults.standard.set(true, forKey: StoreKey.binReconciled)
    }
    
    // MARK: - Tombstones
    
    private func persistLedger() {
        guard persistsLedger else { return }
        UserDefaults.standard.set(ledger.encoded(), forKey: StoreKey.tombstones)
    }
    
    @discardableResult
    private func flushTombstones() async -> Bool {
        var succeeded = true
        for table in SyncTable.all {
            let pending = ledger.unconfirmedIds(table: table)
            guard !pending.isEmpty else { continue }
            for chunk in pending.chunked(into: deleteBatchSize) {
                if await deleteRows(table: table, ids: chunk) {
                    ledger.confirm(table: table, ids: chunk)
                } else {
                    succeeded = false
                    break
                }
            }
        }
        ledger.pruneConfirmed()
        persistLedger()
        return succeeded
    }
    
    // MARK: - HTTP Helpers (with auto-refresh on 401)
    
    private func upsert(table: String, payload: [[String: Any]]) async -> Bool {
        guard !payload.isEmpty else { return true }
        guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/\(table)") else { return false }
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
        guard let url = components.url else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("[Supabase] Serialization error for \(table): \(error)")
            lastError = "Serialization error: \(error.localizedDescription)"
            return false
        }
        
        guard let (data, response) = await authenticatedRequest(request) else { return false }
        
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            // A database without the habit link column must not block ordinary task syncing.
            if table == SyncTable.tasks, tasksSupportHabitId, Self.mentionsMissingHabitIdColumn(body) {
                print("[Supabase] tasks.habit_id is missing; habit links will stay device-local. Add the column to sync them.")
                tasksSupportHabitId = false
                let stripped = payload.map { row in row.filter { $0.key != "habit_id" } }
                return await upsert(table: table, payload: stripped)
            }
        }
        
        return validate(response: response, data: data, action: "Upsert \(table)")
    }
    
    /// Recognises PostgREST's schema-cache and Postgres' undefined-column errors.
    static func mentionsMissingHabitIdColumn(_ body: String) -> Bool {
        let lowered = body.lowercased()
        guard lowered.contains("habit_id") else { return false }
        return lowered.contains("pgrst204")
            || lowered.contains("42703")
            || lowered.contains("could not find")
            || lowered.contains("does not exist")
    }
    
    private func deleteRows(table: String, ids: [String]) async -> Bool {
        guard let uid = userId else { return false }
        guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/\(table)") else { return false }
        components.queryItems = [
            URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
            URLQueryItem(name: "user_id", value: "eq.\(uid)")
        ]
        guard let url = components.url else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        guard let (data, response) = await authenticatedRequest(request) else { return false }
        return validate(response: response, data: data, action: "Delete \(table)")
    }
    
    /// Reads a whole table in pages. Returns `nil` unless the full snapshot was retrieved.
    private func fetchAll<T: Decodable>(table: String, uid: String, filterByUserId: Bool = true) async -> [T]? {
        var results: [T] = []
        var offset = 0
        
        for _ in 0..<maxPages {
            guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/\(table)") else { return nil }
            var queryItems = [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "id.asc"),
                URLQueryItem(name: "limit", value: "\(pageSize)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
            if filterByUserId {
                queryItems.insert(URLQueryItem(name: "user_id", value: "eq.\(uid)"), at: 1)
            }
            components.queryItems = queryItems
            guard let url = components.url else { return nil }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            guard let (data, response) = await authenticatedRequest(request),
                  validate(response: response, data: data, action: "Fetch \(table)") else { return nil }
            
            let rows: [FailableRow<T>]
            do {
                rows = try JSONDecoder().decode([FailableRow<T>].self, from: data)
            } catch {
                print("[Supabase] Decode \(table) error: \(error)")
                lastError = "Decode \(table) error: \(error.localizedDescription)"
                return nil
            }
            
            let decoded = rows.compactMap { $0.value }
            if decoded.count < rows.count {
                print("[Supabase] Skipped \(rows.count - decoded.count) unreadable \(table) row(s)")
            }
            results.append(contentsOf: decoded)
            
            // A short page is the last page.
            if rows.count < pageSize { return results }
            offset += pageSize
        }
        return results
    }
    
    private func validate(response: URLResponse, data: Data, action: String) -> Bool {
        guard let httpResp = response as? HTTPURLResponse else { return false }
        if httpResp.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if Self.mentionsMissingTable(body) {
                print("[Supabase] \(action) table missing on remote server; operating locally.")
                return false
            }
            let msg = "\(action) error (HTTP \(httpResp.statusCode)): \(body)"
            print("[Supabase] \(msg)")
            lastError = msg
            return false
        }
        lastError = nil
        return true
    }
    
    static func mentionsMissingTable(_ body: String) -> Bool {
        let lowered = body.lowercased()
        return lowered.contains("pgrst205")
            || lowered.contains("42p01")
            || lowered.contains("could not find the table")
            || lowered.contains("does not exist")
    }
    
    /// Sends a request with auth headers. Retries once on 401 after refreshing the session.
    private func authenticatedRequest(_ request: URLRequest, allowRetry: Bool = true) async -> (Data, URLResponse)? {
        var req = request
        req.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        
        let sentAt = Date()
        do {
            let (data, response) = try await session.data(for: req)
            updateServerClock(from: response, sentAt: sentAt)
            
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 401, allowRetry {
                if await refreshAccessToken() {
                    return await authenticatedRequest(request, allowRetry: false)
                }
                return nil
            }
            
            return (data, response)
        } catch {
            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                return nil
            }
            print("[Supabase] Request error: \(error)")
            lastError = "Network error: \(error.localizedDescription)"
            return nil
        }
    }
    
    private func updateServerClock(from response: URLResponse, sentAt: Date) {
        guard let httpResp = response as? HTTPURLResponse,
              let serverDate = ServerClock.parseHTTPDate(httpResp.value(forHTTPHeaderField: "Date")) else { return }
        if clock.adopt(serverDate: serverDate, sentAt: sentAt, receivedAt: Date()) {
            UserDefaults.standard.set(clock.offset, forKey: StoreKey.serverTimeOffset)
        }
    }
    
    private func noteSyncSuccess() {
        backoff.recordSuccess()
        lastSyncedAt = Date()
    }
    
    // MARK: - List Collaborator Management
    
    func fetchMembers(for listId: String) async -> [ScratchpadMemberDTO] {
        guard isAuthenticated, let _ = userId else { return [] }
        await ensureFreshToken()
        
        guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/\(SyncTable.scratchpadListMembers)") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "list_id", value: "eq.\(listId)"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        guard let url = components.url else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        guard let (data, response) = await authenticatedRequest(request),
              validate(response: response, data: data, action: "Fetch members") else { return [] }
        
        do {
            return try JSONDecoder().decode([ScratchpadMemberDTO].self, from: data)
        } catch {
            print("[Supabase] Decode members error: \(error)")
            return []
        }
    }
    
    func inviteCollaborator(listId: String, email: String) async -> (success: Bool, error: String?) {
        guard isAuthenticated, let uid = userId else { return (false, "Not authenticated") }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
            return (false, "Invalid email address".localized)
        }
        await ensureFreshToken()
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/\(SyncTable.scratchpadListMembers)") else {
            return (false, "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var payload: [String: Any] = [
            "list_id": listId,
            "owner_id": uid,
            "invited_email": trimmedEmail,
            "role": "editor"
        ]
        if let email = userEmail, !email.isEmpty {
            payload["owner_email"] = email
        }
        
        func createRequest(with bodyDict: [String: Any]) -> URLRequest? {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)
            return req
        }
        
        guard let request = createRequest(with: payload) else {
            return (false, "Serialization error")
        }
        
        guard var (data, response) = await authenticatedRequest(request) else {
            return (false, "Network error")
        }
        
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.contains("owner_email") {
                // If owner_email column is not yet present on remote DB, retry without it
                var fallbackPayload = payload
                fallbackPayload.removeValue(forKey: "owner_email")
                if let fallbackReq = createRequest(with: fallbackPayload),
                   let (retryData, retryResp) = await authenticatedRequest(fallbackReq) {
                    data = retryData
                    response = retryResp
                }
            }
        }
        
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.contains("duplicate") || body.contains("unique") || body.contains("23505") {
                return (false, "User already invited")
            }
            return (false, "Error (HTTP \(httpResp.statusCode)): \(body)")
        }
        
        return (true, nil)
    }
    
    func removeCollaborator(memberId: String) async -> Bool {
        guard isAuthenticated else { return false }
        await ensureFreshToken()
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/\(SyncTable.scratchpadListMembers)?id=eq.\(memberId)") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        guard let (data, response) = await authenticatedRequest(request) else { return false }
        return validate(response: response, data: data, action: "Remove member")
    }
    
    func leaveSharedList(listId: String) async -> Bool {
        guard isAuthenticated, let uid = userId else { return false }
        await ensureFreshToken()
        
        let email = (userEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/\(SyncTable.scratchpadListMembers)") else {
            return false
        }
        
        var queryItems = [URLQueryItem(name: "list_id", value: "eq.\(listId)")]
        if !email.isEmpty {
            queryItems.append(URLQueryItem(name: "or", value: "(member_user_id.eq.\(uid),invited_email.ilike.\(email))"))
        } else {
            queryItems.append(URLQueryItem(name: "member_user_id", value: "eq.\(uid)"))
        }
        components.queryItems = queryItems
        
        guard let url = components.url else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        guard let (data, response) = await authenticatedRequest(request) else { return false }
        return validate(response: response, data: data, action: "Leave list")
    }
}

// MARK: - Test Seams

#if DEBUG
/// Lets the tests drive the real merge, payload and tombstone code against an in-memory
/// store. Nothing here performs any networking, and none of it is compiled into a release
/// build.
extension SupabaseSyncManager {
    static func makeForTesting(context: ModelContext, uid: String = "test-user") -> SupabaseSyncManager {
        let manager = SupabaseSyncManager()
        manager.persistsLedger = false
        manager.ledger = TombstoneLedger()
        manager.modelContext = context
        manager.userId = uid
        manager.isAuthenticated = false
        return manager
    }
    
    var testingClockOffset: TimeInterval {
        get { clock.offset }
        set { clock.offset = newValue }
    }
    
    var testingLedger: TombstoneLedger {
        get { ledger }
        set { ledger = newValue }
    }
    
    var testingSupportsHabitIdColumn: Bool {
        get { tasksSupportHabitId }
        set { tasksSupportHabitId = newValue }
    }
    
    var testingUserId: String? { userId }
    
    /// Applies a complete server snapshot. Returns whether a follow-up push is needed.
    @discardableResult
    func testingMerge(tasks: [SupabaseTaskDTO], habits: [SupabaseHabitDTO] = []) -> Bool {
        guard let context = modelContext, let uid = userId else { return false }
        var needsFollowup = mergeRemoteTasks(tasks, context: context, uid: uid)
        if mergeRemoteHabits(habits, context: context, uid: uid) { needsFollowup = true }
        persist(context)
        return needsFollowup
    }
    
    func testingArmLegacyBinPurge() {
        legacyBinPurgeArmed = true
    }
    
    /// The rows a push would send, after local housekeeping.
    func testingPushableTasks() -> [TaskItem] {
        guard let context = modelContext else { return [] }
        return pushableTasks(context: context).filter { needsPush($0) }
    }
    
    func testingPushableHabits() -> [HabitItem] {
        guard let context = modelContext else { return [] }
        return pushableHabits(context: context).filter { needsPush($0) }
    }
    
    /// The exact body a push would upload for one row.
    func testingTaskPayload(_ task: TaskItem) -> [String: Any] {
        taskPayload(task, uid: userId ?? "")
    }
    
    func testingHabitPayload(_ habit: HabitItem) -> [String: Any] {
        habitPayload(habit, uid: userId ?? "")
    }
    
    func testingMarkSynced(_ task: TaskItem) {
        task.syncedAt = task.updatedAt
    }
    
    func testingMarkSynced(_ habit: HabitItem) {
        habit.syncedAt = habit.updatedAt
    }
    
    func testingNeedsPush(_ task: TaskItem) -> Bool { needsPush(task) }
    func testingNeedsPush(_ habit: HabitItem) -> Bool { needsPush(habit) }
    
    func testingSave() {
        guard let context = modelContext else { return }
        persist(context)
    }
}
#endif

// MARK: - Utilities

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
