import Foundation
import SwiftData

@Model
final class TaskItem {
    var id: String = UUID().uuidString
    var text: String = ""
    var completed: Bool = false
    var createdAt: Date = Date()
    var intervalType: String = ""
    var order: Int = 0
    var deletedAt: Date? = nil
    var completedAt: Date? = nil
    var updatedAt: Date = Date()
    /// Value of `updatedAt` at the time the row was last confirmed by the server.
    /// `nil`, or older than `updatedAt`, means the row still has unpublished local changes.
    var syncedAt: Date? = nil

    init(text: String, intervalType: String, order: Int = 0) {
        self.id = UUID().uuidString
        self.text = text
        self.completed = false
        self.createdAt = Date()
        self.intervalType = intervalType
        self.order = order
        self.deletedAt = nil
        self.completedAt = nil
        self.updatedAt = Date()
        self.syncedAt = nil
    }
}
