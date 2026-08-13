import Foundation
import SwiftData

@Model
final class ScratchpadList {
    var id: String = UUID().uuidString
    var title: String = ""
    var order: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date? = nil
    var syncedAt: Date? = nil

    init(title: String, order: Int = 0) {
        self.id = UUID().uuidString
        self.title = title
        self.order = order
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncedAt = nil
    }
}

@Model
final class ScratchpadItem {
    var id: String = UUID().uuidString
    var listId: String = ""
    var text: String = ""
    var completed: Bool = false
    var order: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date? = nil
    var completedAt: Date? = nil
    var syncedAt: Date? = nil

    init(listId: String, text: String, order: Int = 0) {
        self.id = UUID().uuidString
        self.listId = listId
        self.text = text
        self.completed = false
        self.order = order
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.completedAt = nil
        self.syncedAt = nil
    }
}
