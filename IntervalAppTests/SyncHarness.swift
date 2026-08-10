import Foundation
import SwiftData
import XCTest

// A deterministic stand-in for the Supabase tables plus one or more devices talking to them.
//
// The harness deliberately reuses the production code: rows are uploaded through
// `taskPayload`, serialised to JSON, decoded through the same DTOs the app decodes, and
// merged by the app's own merge. Only the transport is fake, so a sync bug shows up here
// rather than only on a second physical device.

/// An in-memory table set that behaves like PostgREST upsert-on-id: the last writer wins,
/// unconditionally. Choosing what to send is the client's job, which is exactly what the
/// tests are checking.
@MainActor
final class FakeSupabase {
    private var rows: [String: [String: [String: Any]]] = [
        SyncTable.tasks: [:],
        SyncTable.habits: [:]
    ]
    
    private(set) var upsertCount = 0
    private(set) var deleteCount = 0
    
    func upsert(table: String, payload: [String: Any]) {
        guard let id = payload["id"] as? String else { return XCTFail("Payload without an id") }
        rows[table]?[id] = payload
        upsertCount += 1
    }
    
    func delete(table: String, ids: [String]) {
        for id in ids { rows[table]?.removeValue(forKey: id) }
        deleteCount += ids.count
    }
    
    func ids(table: String) -> Set<String> {
        Set((rows[table] ?? [:]).keys)
    }
    
    func value(table: String, id: String, key: String) -> Any? {
        rows[table]?[id]?[key]
    }
    
    func text(table: String, id: String) -> String? {
        value(table: table, id: id, key: "text") as? String
    }
    
    /// Injects a row the app never wrote: another user's data, a malformed value, a row from
    /// an older schema.
    func injectRaw(table: String, id: String, row: [String: Any]) {
        rows[table]?[id] = row
    }
    
    /// Simulates a database whose schema predates a column.
    func removeColumn(table: String, key: String) {
        for (id, var row) in rows[table] ?? [:] {
            row.removeValue(forKey: key)
            rows[table]?[id] = row
        }
    }
    
    /// Serialises and decodes exactly as a real response would, so payload keys and timestamp
    /// formats are covered too.
    func taskSnapshot() throws -> [SupabaseTaskDTO] {
        try snapshot(table: SyncTable.tasks)
    }
    
    func habitSnapshot() throws -> [SupabaseHabitDTO] {
        try snapshot(table: SyncTable.habits)
    }
    
    private func snapshot<T: Decodable>(table: String) throws -> [T] {
        let payloads = Array((rows[table] ?? [:]).values)
        let data = try JSONSerialization.data(withJSONObject: payloads)
        return try JSONDecoder().decode([T].self, from: data)
    }
}

/// One device: its own local store and its own sync manager state.
@MainActor
final class SyncDevice {
    let store: TestStore
    let manager: SupabaseSyncManager
    
    init(uid: String = "test-user", clockOffset: TimeInterval = 0) throws {
        store = try TestStore()
        manager = SupabaseSyncManager.makeForTesting(context: store.context, uid: uid)
        manager.testingClockOffset = clockOffset
    }
    
    // MARK: - Local edits
    
    @discardableResult
    func createTask(_ text: String, interval: String = "1 Day", order: Int = 0, at time: Date, id: String? = nil) -> TaskItem {
        let task = store.addTask(text, interval: interval, order: order, id: id, updatedAt: time)
        task.createdAt = time
        return task
    }
    
    @discardableResult
    func createHabit(_ text: String, order: Int = 0, at time: Date, id: String? = nil) -> HabitItem {
        store.addHabit(text, order: order, id: id, updatedAt: time)
    }
    
    func edit(_ task: TaskItem, text: String, at time: Date) {
        task.text = text
        task.updatedAt = time
    }
    
    /// Mirrors what the app does for a permanent delete: record it, then remove the row.
    func hardDelete(_ task: TaskItem) {
        manager.deleteRemote(table: SyncTable.tasks, ids: [task.id])
        store.context.delete(task)
    }
    
    func softDelete(_ task: TaskItem, at time: Date) {
        task.deletedAt = time
        task.updatedAt = time
    }
    
    // MARK: - Sync
    
    /// Pending deletes first, then dirty rows, matching the order a real push uses.
    func push(to server: FakeSupabase, at time: Date = Date()) {
        var ledger = manager.testingLedger
        for table in SyncTable.all {
            let pending = ledger.unconfirmedIds(table: table)
            guard !pending.isEmpty else { continue }
            server.delete(table: table, ids: pending)
            ledger.confirm(table: table, ids: pending, now: time)
        }
        ledger.pruneConfirmed(now: time)
        manager.testingLedger = ledger
        
        for task in manager.testingPushableTasks() {
            server.upsert(table: SyncTable.tasks, payload: manager.testingTaskPayload(task))
            manager.testingMarkSynced(task)
        }
        for habit in manager.testingPushableHabits() {
            server.upsert(table: SyncTable.habits, payload: manager.testingHabitPayload(habit))
            manager.testingMarkSynced(habit)
        }
        manager.testingSave()
    }
    
    @discardableResult
    func pull(from server: FakeSupabase) throws -> Bool {
        try manager.testingMerge(tasks: server.taskSnapshot(), habits: server.habitSnapshot())
    }
    
    /// A full cycle, as the poll timer would run it.
    func sync(with server: FakeSupabase, at time: Date = Date()) throws {
        push(to: server, at: time)
        try pull(from: server)
        push(to: server, at: time)
    }
    
    // MARK: - Inspection
    
    func tasks() throws -> [TaskItem] {
        try store.tasks()
    }
    
    func task(id: String) throws -> TaskItem? {
        try store.tasks().first { $0.id == id }
    }
    
    func taskTexts() throws -> [String] {
        try store.tasks().map { $0.text }.sorted()
    }
    
    func habit(id: String) throws -> HabitItem? {
        try store.habits().first { $0.id == id }
    }
    
    var hasNothingToPush: Bool {
        manager.testingPushableTasks().isEmpty && manager.testingPushableHabits().isEmpty
    }
}
