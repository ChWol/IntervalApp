import Foundation
import SwiftData

extension Notification.Name {
    static let persistenceSaveFailed = Notification.Name("persistenceSaveFailed")
    static let flushPendingEdits = Notification.Name("flushPendingEdits")
}

/// One save path for user-authored data. A failed save leaves the context's
/// pending changes intact, reports the failure, and returns false so destructive
/// flows such as logout can stop before discarding the local recovery copy.
@MainActor
enum PersistenceSafety {
    static func save(_ context: ModelContext, operation: String = "Saving changes") -> Bool {
        attempt(operation: operation, save: { try context.save() }) { message in
            print("[Persistence] \(message)")
            NotificationCenter.default.post(
                name: .persistenceSaveFailed,
                object: nil,
                userInfo: ["message": message]
            )
        }
    }

    static func attempt(
        operation: String,
        save: () throws -> Void,
        report: (String) -> Void
    ) -> Bool {
        do {
            try save()
            return true
        } catch {
            report("\(operation) failed. Your changes are still pending locally. \(error.localizedDescription)")
            return false
        }
    }

    /// A background transition must never advertise changes for upload unless
    /// the final local save succeeded. Failed saves remain pending for retry.
    static func prepareForBackground(
        save: () -> Bool,
        scheduleSync: () -> Void
    ) {
        if save() {
            scheduleSync()
        }
    }
}
