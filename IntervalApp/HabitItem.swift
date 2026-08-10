import Foundation
import SwiftData

@Model
final class HabitItem {
    var id: String = UUID().uuidString
    var text: String = ""
    var frequency: String = "Daily"
    var streak: Int = 0
    var lastCompletedDate: Date? = nil
    var order: Int = 0
    var deletedAt: Date? = nil
    var updatedAt: Date = Date()
    /// Value of `updatedAt` at the time the row was last confirmed by the server.
    /// `nil`, or older than `updatedAt`, means the row still has unpublished local changes.
    var syncedAt: Date? = nil
    
    init(text: String, frequency: String = "Daily", order: Int = 0) {
        self.id = UUID().uuidString
        self.text = text
        self.frequency = frequency
        self.streak = 0
        self.order = order
        self.deletedAt = nil
        self.updatedAt = Date()
        self.syncedAt = nil
    }
    
    var isCompletedCurrentPeriod: Bool {
        isCompleted(at: Date())
    }
    
    /// Whether the habit counts as done for the period containing `date`.
    /// Callers that pass an explicit `date` keep tests and midnight edges deterministic.
    func isCompleted(at date: Date, calendar: Calendar = .current) -> Bool {
        guard let last = lastCompletedDate else { return false }
        if frequency == "Daily" {
            return calendar.isDate(last, inSameDayAs: date)
        }
        return calendar.isDate(last, equalTo: date, toGranularity: .weekOfYear)
    }
}
