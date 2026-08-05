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
    
    init(text: String, frequency: String = "Daily", order: Int = 0) {
        self.id = UUID().uuidString
        self.text = text
        self.frequency = frequency
        self.streak = 0
        self.order = order
    }
    
    var isCompletedCurrentPeriod: Bool {
        guard let last = lastCompletedDate else { return false }
        let cal = Calendar.current
        if frequency == "Daily" {
            return cal.isDateInToday(last)
        } else {
            return cal.isDate(last, equalTo: Date(), toGranularity: .weekOfYear)
        }
    }
}
