#if os(iOS)
import ActivityKit

@available(iOS 16.1, *)
public struct IntervalFocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var taskTitles: [String]
        public var remainingMinutes: Int

        public init(taskTitles: [String], remainingMinutes: Int) {
            self.taskTitles = taskTitles
            self.remainingMinutes = remainingMinutes
        }
    }

    public var intervalTitle: String

    public init(intervalTitle: String = "1 Hour") {
        self.intervalTitle = intervalTitle
    }
}
#endif
