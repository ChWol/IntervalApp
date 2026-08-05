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

    init(text: String, intervalType: String, order: Int = 0) {
        self.id = UUID().uuidString
        self.text = text
        self.completed = false
        self.createdAt = Date()
        self.intervalType = intervalType
        self.order = order
        self.deletedAt = nil
        self.completedAt = nil
    }
}
