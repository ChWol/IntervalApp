import Foundation

// The decision-making parts of syncing, kept free of networking and of SwiftData so that
// every rule can be exercised directly by the unit tests.

// MARK: - Tables

enum SyncTable {
    static let tasks = "tasks"
    static let habits = "habits"
    static let all = [tasks, habits]
}

// MARK: - Timestamps

/// Reads and writes the timestamp formats Postgres and PostgREST can produce.
enum SyncTimestamp {
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
    
    /// Covers values with a space separator or no timezone at all, which the ISO8601
    /// formatters reject. A missing timezone is UTC by Postgres convention.
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
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()
    
    static func format(_ date: Date) -> String {
        iso8601WithFraction.string(from: date)
    }
    
    static func parse(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty else { return nil }
        
        if let date = iso8601WithFraction.date(from: string) { return date }
        if let date = iso8601Plain.date(from: string) { return date }
        
        for format in fallbackFormats {
            fallbackFormatter.dateFormat = format
            if let date = fallbackFormatter.date(from: string) { return date }
        }
        
        return nil
    }
}

// MARK: - Server Clock

/// Tracks how far this device's clock sits from the server's, so that `updated_at` can be
/// exchanged in server time. Without this a device with a badly set clock would either win
/// every conflict or ignore every remote change.
struct ServerClock {
    /// Corrections below this are ignored: the HTTP `Date` header only has second
    /// resolution, and stable timestamps matter more than sub-second accuracy.
    static let adoptionThreshold: TimeInterval = 2
    
    var offset: TimeInterval = 0
    
    private static let httpDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return df
    }()
    
    static func parseHTTPDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return httpDateFormatter.date(from: value)
    }
    
    /// Adopts a new offset from one round trip. Returns whether the offset changed.
    @discardableResult
    mutating func adopt(serverDate: Date, sentAt: Date, receivedAt: Date) -> Bool {
        // Midpoint of the round trip best approximates "now" at the moment the server
        // stamped its response.
        let midpoint = sentAt.addingTimeInterval(receivedAt.timeIntervalSince(sentAt) / 2)
        let candidate = serverDate.timeIntervalSince(midpoint)
        guard abs(candidate - offset) > Self.adoptionThreshold else { return false }
        offset = candidate
        return true
    }
    
    func toServer(_ date: Date) -> Date { date.addingTimeInterval(offset) }
    func toLocal(_ date: Date) -> Date { date.addingTimeInterval(-offset) }
}

// MARK: - Merge Policy

enum MergeOutcome: Equatable {
    /// The server copy is newer and should be applied, stamped with this date.
    case adoptRemote(Date)
    /// The local row is newer and still has unpublished changes.
    case keepLocalAndPush
    /// The local row is already in step with the server.
    case keepLocal
    /// The local row has to be sent again: either the server holds an older version of it, or
    /// the server timestamp could not be read and the row needs a comparable one.
    case republishLocal
}

/// Last-write-wins, decided strictly by timestamp. Both timestamps must already be in the
/// same clock frame; see `ServerClock`.
enum MergePolicy {
    static func needsPush(updatedAt: Date, syncedAt: Date?) -> Bool {
        guard let syncedAt else { return true }
        return syncedAt < updatedAt
    }
    
    static func resolve(remoteUpdatedAt: Date?, localUpdatedAt: Date, localSyncedAt: Date?) -> MergeOutcome {
        guard let remoteUpdatedAt else { return .republishLocal }
        if remoteUpdatedAt > localUpdatedAt { return .adoptRemote(remoteUpdatedAt) }
        // The server accepts whatever arrives last, so a device that had queued an older edit
        // can leave an out-of-date row behind. Whoever still holds the newer version has to
        // publish it again, or the two never agree.
        if remoteUpdatedAt < localUpdatedAt { return .republishLocal }
        return needsPush(updatedAt: localUpdatedAt, syncedAt: localSyncedAt) ? .keepLocalAndPush : .keepLocal
    }
}

// MARK: - Tombstones

/// A row destroyed on this device. It is kept until the server confirms the delete so that
/// a pull cannot resurrect it, and so an offline delete survives a restart.
struct Tombstone: Codable, Equatable {
    let id: String
    let createdAt: Date
    var confirmedAt: Date?
}

/// Record of pending and recently completed deletes. Pure value type: the sync manager owns
/// loading and saving the encoded form.
struct TombstoneLedger: Codable, Equatable {
    /// Confirmed entries are held this long so a snapshot fetched before the delete cannot
    /// reintroduce the row, then dropped to keep the record from growing without bound.
    static let confirmedRetention: TimeInterval = 15 * 60
    
    private var entries: [String: [String: Tombstone]] = [:]
    
    init() {}
    
    mutating func add(table: String, ids: [String], now: Date = Date()) {
        var forTable = entries[table] ?? [:]
        for id in ids where forTable[id] == nil {
            forTable[id] = Tombstone(id: id, createdAt: now, confirmedAt: nil)
        }
        entries[table] = forTable
    }
    
    func contains(table: String, id: String) -> Bool {
        entries[table]?[id] != nil
    }
    
    func unconfirmedIds(table: String) -> [String] {
        (entries[table] ?? [:]).values.filter { $0.confirmedAt == nil }.map { $0.id }.sorted()
    }
    
    mutating func confirm(table: String, ids: [String], now: Date = Date()) {
        guard var forTable = entries[table] else { return }
        for id in ids {
            forTable[id]?.confirmedAt = now
        }
        entries[table] = forTable
    }
    
    mutating func pruneConfirmed(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.confirmedRetention)
        for (table, tableEntries) in entries {
            entries[table] = tableEntries.filter { _, tombstone in
                guard let confirmedAt = tombstone.confirmedAt else { return true }
                return confirmedAt > cutoff
            }
        }
        entries = entries.filter { !$0.value.isEmpty }
    }
    
    mutating func removeAll() {
        entries.removeAll()
    }
    
    var isEmpty: Bool { entries.allSatisfy { $0.value.isEmpty } }
    
    func count(table: String) -> Int { entries[table]?.count ?? 0 }
    
    static func decode(from data: Data?) -> TombstoneLedger {
        guard let data, let ledger = try? JSONDecoder().decode(TombstoneLedger.self, from: data) else {
            return TombstoneLedger()
        }
        return ledger
    }
    
    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}

// MARK: - Retry Backoff

/// Spaces out scheduled sync attempts while the server is unreachable. Manual and
/// edit-triggered syncs bypass this.
struct SyncBackoff {
    static let maxDelay: TimeInterval = 120
    static let maxExponent = 8
    
    private(set) var consecutiveFailures = 0
    private(set) var nextAttempt: Date = .distantPast
    
    init() {}
    
    func allowsAttempt(now: Date = Date()) -> Bool {
        now >= nextAttempt
    }
    
    mutating func recordSuccess() {
        consecutiveFailures = 0
        nextAttempt = .distantPast
    }
    
    mutating func recordFailure(now: Date = Date()) {
        consecutiveFailures = min(consecutiveFailures + 1, Self.maxExponent)
        nextAttempt = now.addingTimeInterval(min(Self.maxDelay, pow(2, Double(consecutiveFailures))))
    }
}
