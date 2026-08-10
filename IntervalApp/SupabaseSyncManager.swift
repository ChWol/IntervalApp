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

/// Wrapper that turns an undecodable row into `nil` instead of failing the whole array.
private struct FailableRow<T: Decodable>: Decodable {
    let value: T?
    
    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}

/// A locally destroyed row. Kept until the server confirms the delete so that a pull can
/// never resurrect it, and so an offline delete survives an app restart.
private struct Tombstone: Codable {
    let id: String
    let createdAt: Date
    var confirmedAt: Date?
}

// MARK: - Supabase Sync Manager

@MainActor
class SupabaseSyncManager: ObservableObject {
    static let shared = SupabaseSyncManager()
    
    private let supabaseURL = "https://mrqgudqemlgdxnrqxqtk.supabase.co"
    private let supabaseKey = "sb_publishable_KV6DvqpKbl6wmMZvcwPczw_ID2hOShH"
    
    private enum Table {
        static let tasks = "tasks"
        static let habits = "habits"
        static let all = [tasks, habits]
    }
    
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
    private let tombstoneRetention: TimeInterval = 15 * 60
    private let maxBackoff: TimeInterval = 120
    
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
    private var userId: String? {
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
    
    /// Difference between the server clock and this device's clock. All `updated_at` values are
    /// exchanged in server time so that a badly set device clock cannot win every conflict.
    private var serverTimeOffset: TimeInterval = 0
    
    private var tombstones: [String: [String: Tombstone]] = [:]
    /// Rows missing from the previous server snapshot. A row must be absent twice in a row
    /// before it is deleted locally, so a single incomplete snapshot cannot destroy data.
    private var missingTaskIds = Set<String>()
    private var missingHabitIds = Set<String>()
    
    /// Builds before per-row sync tracking hard-deleted rows locally without recording a
    /// tombstone, leaving orphaned soft-deleted rows on the server. They are cleared out once,
    /// on the first successful pull after the upgrade, and only for stores that already hold
    /// data — on a fresh install those same rows are the user's real recycle bin.
    private var legacyBinPurgeArmed = false
    
    private var consecutiveFailures = 0
    private var nextScheduledAttempt: Date = .distantPast
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    // MARK: - Date Formatting & Parsing
    
    private static let iso8601WithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    /// Fallbacks for the shapes Postgres and PostgREST can emit, including values with a
    /// space separator or no timezone at all (which the ISO8601 formatters reject).
    private static let fallbackFormats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
        "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ",
        "yyyy-MM-dd HH:mm:ssZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss.SSSSSS",
        "yyyy-MM-dd HH:mm:ss"
    ]
    
    private static let fallbackFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        // Timestamps without an explicit zone are UTC by Postgres convention.
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()
    
    private static let httpDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return df
    }()
    
    private static func formatDate(_ date: Date) -> String {
        iso8601WithFraction.string(from: date)
    }
    
    private static func parseDate(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty else { return nil }
        
        if let date = iso8601WithFraction.date(from: string) { return date }
        if let date = iso8601Plain.date(from: string) { return date }
        
        for format in fallbackFormats {
            fallbackFormatter.dateFormat = format
            if let date = fallbackFormatter.date(from: string) { return date }
        }
        
        return nil
    }
    
    private init() {
        let defaults = UserDefaults.standard
        accessToken = defaults.string(forKey: StoreKey.accessToken)
        refreshToken = defaults.string(forKey: StoreKey.refreshToken)
        userId = defaults.string(forKey: StoreKey.userId)
        userEmail = defaults.string(forKey: StoreKey.userEmail)
        isAuthenticated = accessToken != nil && userId != nil
        serverTimeOffset = defaults.double(forKey: StoreKey.serverTimeOffset)
        if let expiry = defaults.object(forKey: StoreKey.tokenExpiry) as? Double {
            accessTokenExpiry = Date(timeIntervalSince1970: expiry)
        }
        loadTombstones()
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
    
    func signOut() {
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
        UserDefaults.standard.removeObject(forKey: StoreKey.userEmail)
        UserDefaults.standard.removeObject(forKey: StoreKey.accessToken)
        UserDefaults.standard.removeObject(forKey: StoreKey.refreshToken)
        UserDefaults.standard.removeObject(forKey: StoreKey.userId)
        UserDefaults.standard.removeObject(forKey: StoreKey.tokenExpiry)
    }
    
    private func handleAuthSuccess(_ response: AuthResponse, email: String) {
        // Signing in as somebody else must not upload the previous account's rows.
        let previousUserId = userId
        if let previousUserId, previousUserId != response.user.id {
            pendingLocalPurge = true
            tombstones.removeAll()
            persistTombstones()
            missingTaskIds.removeAll()
            missingHabitIds.removeAll()
        }
        
        applyTokens(response)
        userId = response.user.id
        userEmail = email
        UserDefaults.standard.set(email, forKey: StoreKey.userEmail)
        isAuthenticated = true
        
        if let ctx = modelContext {
            if pendingLocalPurge {
                purgeLocalStore(context: ctx)
                pendingLocalPurge = false
            }
            startSync(context: ctx)
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
            await runSyncCycle(force: true)
        }
    }
    
    /// Push then pull. Scheduled cycles respect the retry backoff; user- and edit-triggered
    /// cycles are always attempted.
    @discardableResult
    private func runSyncCycle(force: Bool) async -> Bool {
        guard isAuthenticated else { return false }
        if !force && Date() < nextScheduledAttempt { return false }
        
        let pushed = await pushToSupabase()
        let pulled = await pullFromSupabase()
        return pushed && pulled
    }
    
    /// Instant push call (fire and forget)
    func push() {
        guard isAuthenticated else { return }
        debounceTimer?.cancel()
        Task { @MainActor in await pushToSupabase() }
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
        addTombstones(table: table, ids: ids)
        guard isAuthenticated else { return }
        Task { @MainActor in
            await ensureFreshToken()
            await flushTombstones()
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
                Task { @MainActor in await pushToSupabase() }
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
            guard await upsert(table: Table.tasks, payload: payload) else {
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
            guard await upsert(table: Table.habits, payload: payload) else {
                succeeded = false
                break
            }
            for (index, habit) in chunk.enumerated() {
                habit.syncedAt = stamps[index]
            }
        }
        
        persist(context)
        
        if succeeded {
            noteSyncSuccess()
        } else {
            noteSyncFailure()
        }
        return succeeded
    }
    
    /// Local housekeeping performed before every push: duplicate ids are collapsed, abandoned
    /// blank rows are removed, and blank editing placeholders are held back from the server.
    private func pushableTasks(context: ModelContext) -> [TaskItem] {
        let byId = deduplicatedTasks(context: context)
        var pushable: [TaskItem] = []
        
        for task in byId.values {
            if isTombstoned(table: Table.tasks, id: task.id) {
                // The row was destroyed for good; a copy reappearing locally is a stale echo.
                context.delete(task)
                continue
            }
            
            let isBlank = task.text.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && task.deletedAt != nil {
                if task.syncedAt != nil {
                    deleteRemote(table: Table.tasks, ids: [task.id])
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
            if isTombstoned(table: Table.habits, id: habit.id) {
                context.delete(habit)
                continue
            }
            if habit.text.trimmingCharacters(in: .whitespaces).isEmpty {
                if habit.syncedAt != nil {
                    deleteRemote(table: Table.habits, ids: [habit.id])
                }
                context.delete(habit)
                continue
            }
            pushable.append(habit)
        }
        return pushable
    }
    
    // Explicit dictionary payloads guarantee key symmetry across the array (PostgREST PGRST102).
    private func taskPayload(_ task: TaskItem, uid: String) -> [String: Any] {
        [
            "id": task.id,
            "text": task.text,
            "completed": task.completed,
            "created_at": Self.formatDate(task.createdAt),
            "interval_type": task.intervalType,
            "order": task.order,
            "deleted_at": task.deletedAt.map { Self.formatDate($0) } ?? NSNull(),
            "completed_at": task.completedAt.map { Self.formatDate($0) } ?? NSNull(),
            "user_id": uid,
            "updated_at": Self.formatDate(toServerTime(task.updatedAt))
        ]
    }
    
    private func habitPayload(_ habit: HabitItem, uid: String) -> [String: Any] {
        [
            "id": habit.id,
            "text": habit.text,
            "frequency": habit.frequency,
            "streak": habit.streak,
            "last_completed_date": habit.lastCompletedDate.map { Self.formatDate($0) } ?? NSNull(),
            "order": habit.order,
            "deleted_at": habit.deletedAt.map { Self.formatDate($0) } ?? NSNull(),
            "user_id": uid,
            "updated_at": Self.formatDate(toServerTime(habit.updatedAt))
        ]
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
                Task { @MainActor in await pullFromSupabase() }
            }
        }
        
        await ensureFreshToken()
        
        // Both snapshots must be complete before anything is merged: a partial snapshot must
        // never be mistaken for rows having been deleted elsewhere.
        guard let remoteTasks: [SupabaseTaskDTO] = await fetchAll(table: Table.tasks, uid: uid),
              let remoteHabits: [SupabaseHabitDTO] = await fetchAll(table: Table.habits, uid: uid) else {
            noteSyncFailure()
            return false
        }
        
        var needsFollowupPush = mergeRemoteTasks(remoteTasks, context: context, uid: uid)
        if mergeRemoteHabits(remoteHabits, context: context, uid: uid) {
            needsFollowupPush = true
        }
        
        persist(context)
        completeLegacyBinPurge()
        noteSyncSuccess()
        
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
            
            if isTombstoned(table: Table.tasks, id: dto.id) {
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
            
            let remoteStamp = Self.parseDate(dto.updated_at).map { toLocalTime($0) }
            
            if let existing = localById[dto.id] {
                guard let stamp = remoteStamp else {
                    // Unreadable server timestamp: republish ours so the row is comparable again.
                    existing.syncedAt = nil
                    needsFollowupPush = true
                    continue
                }
                if stamp > existing.updatedAt {
                    var changed = false
                    changed = assign(text, to: existing, \.text) || changed
                    changed = assign(dto.completed ?? existing.completed, to: existing, \.completed) || changed
                    changed = assign(dto.interval_type ?? existing.intervalType, to: existing, \.intervalType) || changed
                    changed = assign(dto.order ?? existing.order, to: existing, \.order) || changed
                    changed = assign(Self.parseDate(dto.created_at) ?? existing.createdAt, to: existing, \.createdAt) || changed
                    changed = assign(Self.parseDate(dto.deleted_at), to: existing, \.deletedAt) || changed
                    changed = assign(Self.parseDate(dto.completed_at), to: existing, \.completedAt) || changed
                    if changed { existing.updatedAt = stamp }
                    if existing.syncedAt != stamp { existing.syncedAt = stamp }
                } else if needsPush(existing) {
                    needsFollowupPush = true
                }
            } else {
                if dto.deleted_at != nil && legacyBinPurgeArmed {
                    orphanRemoteIds.append(dto.id)
                    continue
                }
                
                let task = TaskItem(text: text, intervalType: dto.interval_type ?? "1 Day", order: dto.order ?? 0)
                task.id = dto.id
                task.completed = dto.completed ?? false
                task.createdAt = Self.parseDate(dto.created_at) ?? Date()
                task.deletedAt = Self.parseDate(dto.deleted_at)
                task.completedAt = Self.parseDate(dto.completed_at)
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
            deleteRemote(table: Table.tasks, ids: orphanRemoteIds)
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
            
            if isTombstoned(table: Table.habits, id: dto.id) {
                if let stale = localById.removeValue(forKey: dto.id) { context.delete(stale) }
                continue
            }
            
            let text = (dto.text ?? "").trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                if localById[dto.id] == nil { orphanRemoteIds.append(dto.id) }
                continue
            }
            
            let remoteStamp = Self.parseDate(dto.updated_at).map { toLocalTime($0) }
            
            if let existing = localById[dto.id] {
                guard let stamp = remoteStamp else {
                    existing.syncedAt = nil
                    needsFollowupPush = true
                    continue
                }
                if stamp > existing.updatedAt {
                    var changed = false
                    changed = assign(text, to: existing, \.text) || changed
                    changed = assign(dto.frequency ?? existing.frequency, to: existing, \.frequency) || changed
                    changed = assign(dto.streak ?? existing.streak, to: existing, \.streak) || changed
                    changed = assign(Self.parseDate(dto.last_completed_date), to: existing, \.lastCompletedDate) || changed
                    changed = assign(dto.order ?? existing.order, to: existing, \.order) || changed
                    changed = assign(Self.parseDate(dto.deleted_at), to: existing, \.deletedAt) || changed
                    if changed { existing.updatedAt = stamp }
                    if existing.syncedAt != stamp { existing.syncedAt = stamp }
                } else if needsPush(existing) {
                    needsFollowupPush = true
                }
            } else {
                if dto.deleted_at != nil && legacyBinPurgeArmed {
                    orphanRemoteIds.append(dto.id)
                    continue
                }
                
                let habit = HabitItem(text: text, frequency: dto.frequency ?? "Daily", order: dto.order ?? 0)
                habit.id = dto.id
                habit.streak = dto.streak ?? 0
                habit.lastCompletedDate = Self.parseDate(dto.last_completed_date)
                habit.deletedAt = Self.parseDate(dto.deleted_at)
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
            deleteRemote(table: Table.habits, ids: orphanRemoteIds)
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
    
    private func purgeLocalStore(context: ModelContext) {
        for task in (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [] { context.delete(task) }
        for habit in (try? context.fetch(FetchDescriptor<HabitItem>())) ?? [] { context.delete(habit) }
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
        guard let synced = task.syncedAt else { return true }
        return synced < task.updatedAt
    }
    
    private func needsPush(_ habit: HabitItem) -> Bool {
        guard let synced = habit.syncedAt else { return true }
        return synced < habit.updatedAt
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
    
    private func loadTombstones() {
        guard let data = UserDefaults.standard.data(forKey: StoreKey.tombstones),
              let stored = try? JSONDecoder().decode([String: [String: Tombstone]].self, from: data) else { return }
        tombstones = stored
    }
    
    private func persistTombstones() {
        if let data = try? JSONEncoder().encode(tombstones) {
            UserDefaults.standard.set(data, forKey: StoreKey.tombstones)
        }
    }
    
    private func addTombstones(table: String, ids: [String]) {
        var forTable = tombstones[table] ?? [:]
        let now = Date()
        for id in ids where forTable[id] == nil {
            forTable[id] = Tombstone(id: id, createdAt: now, confirmedAt: nil)
        }
        tombstones[table] = forTable
        persistTombstones()
    }
    
    private func isTombstoned(table: String, id: String) -> Bool {
        tombstones[table]?[id] != nil
    }
    
    private func unconfirmedTombstoneIds(table: String) -> [String] {
        (tombstones[table] ?? [:]).values.filter { $0.confirmedAt == nil }.map { $0.id }
    }
    
    private func confirmTombstones(table: String, ids: [String]) {
        guard var forTable = tombstones[table] else { return }
        let now = Date()
        for id in ids {
            forTable[id]?.confirmedAt = now
        }
        tombstones[table] = forTable
    }
    
    /// Confirmed tombstones are kept briefly so that a snapshot fetched before the delete
    /// cannot reintroduce the row, then dropped to keep the record from growing forever.
    private func pruneConfirmedTombstones() {
        let cutoff = Date().addingTimeInterval(-tombstoneRetention)
        for (table, entries) in tombstones {
            tombstones[table] = entries.filter { _, tombstone in
                guard let confirmedAt = tombstone.confirmedAt else { return true }
                return confirmedAt > cutoff
            }
        }
        tombstones = tombstones.filter { !$0.value.isEmpty }
    }
    
    @discardableResult
    private func flushTombstones() async -> Bool {
        var succeeded = true
        for table in Table.all {
            let pending = unconfirmedTombstoneIds(table: table)
            guard !pending.isEmpty else { continue }
            for chunk in pending.chunked(into: deleteBatchSize) {
                if await deleteRows(table: table, ids: chunk) {
                    confirmTombstones(table: table, ids: chunk)
                } else {
                    succeeded = false
                    break
                }
            }
        }
        pruneConfirmedTombstones()
        persistTombstones()
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
        return validate(response: response, data: data, action: "Upsert \(table)")
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
    private func fetchAll<T: Decodable>(table: String, uid: String) async -> [T]? {
        var results: [T] = []
        var offset = 0
        
        for _ in 0..<maxPages {
            guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/\(table)") else { return nil }
            components.queryItems = [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "user_id", value: "eq.\(uid)"),
                URLQueryItem(name: "order", value: "id.asc"),
                URLQueryItem(name: "limit", value: "\(pageSize)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
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
            let msg = "\(action) error (HTTP \(httpResp.statusCode)): \(body)"
            print("[Supabase] \(msg)")
            lastError = msg
            return false
        }
        lastError = nil
        return true
    }
    
    /// Sends a request with auth headers. Retries once on 401 after refreshing the session.
    private func authenticatedRequest(_ request: URLRequest, allowRetry: Bool = true) async -> (Data, URLResponse)? {
        var req = request
        req.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        
        let sentAt = Date()
        do {
            let (data, response) = try await session.data(for: req)
            updateServerTimeOffset(from: response, sentAt: sentAt)
            
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
    
    // MARK: - Clock Alignment & Backoff
    
    /// Tracks the offset between the server clock and this device's clock, so that a device
    /// with a badly set clock neither wins every conflict nor ignores every remote change.
    private func updateServerTimeOffset(from response: URLResponse, sentAt: Date) {
        guard let httpResp = response as? HTTPURLResponse,
              let header = httpResp.value(forHTTPHeaderField: "Date"),
              let serverDate = Self.httpDateFormatter.date(from: header) else { return }
        
        // Midpoint of the round trip is the best estimate of "now" at the moment the
        // server stamped its response.
        let midpoint = sentAt.addingTimeInterval(Date().timeIntervalSince(sentAt) / 2)
        let candidate = serverDate.timeIntervalSince(midpoint)
        
        // The header only has second resolution, so only meaningful corrections are adopted;
        // this keeps stored timestamps stable across syncs.
        guard abs(candidate - serverTimeOffset) > 2 else { return }
        serverTimeOffset = candidate
        UserDefaults.standard.set(candidate, forKey: StoreKey.serverTimeOffset)
    }
    
    private func toServerTime(_ date: Date) -> Date {
        date.addingTimeInterval(serverTimeOffset)
    }
    
    private func toLocalTime(_ date: Date) -> Date {
        date.addingTimeInterval(-serverTimeOffset)
    }
    
    private func noteSyncSuccess() {
        consecutiveFailures = 0
        nextScheduledAttempt = .distantPast
        lastSyncedAt = Date()
    }
    
    /// Backs off scheduled cycles while the server is unreachable instead of retrying every
    /// poll interval. Manual and edit-triggered syncs still go through immediately.
    private func noteSyncFailure() {
        consecutiveFailures = min(consecutiveFailures + 1, 8)
        let delay = min(maxBackoff, pow(2, Double(consecutiveFailures)))
        nextScheduledAttempt = Date().addingTimeInterval(delay)
    }
}

// MARK: - Utilities

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
