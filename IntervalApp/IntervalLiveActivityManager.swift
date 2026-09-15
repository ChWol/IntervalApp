#if os(iOS)
import ActivityKit
import Foundation
import SwiftData

@MainActor
final class IntervalLiveActivityManager {
    static let shared = IntervalLiveActivityManager()
    private init() {}

    func endAll() async {
        for activity in Activity<IntervalFocusActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func refresh(context: ModelContext) async {
        let enabled = UserDefaults.standard.object(forKey: "liveActivitiesEnabled") as? Bool ?? true
        guard enabled else {
            await endAll()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.intervalType == "1 Hour" && task.deletedAt == nil && !task.completed
            },
            sortBy: [SortDescriptor(\TaskItem.order)]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        let titles = Array(tasks.prefix(3)).map { LinkTaskText.displayText(for: $0.text) }
        let state = IntervalFocusActivityAttributes.ContentState(
            taskTitles: titles,
            remainingMinutes: max(0, 60 - Calendar.current.component(.minute, from: Date()))
        )

        for activity in Activity<IntervalFocusActivityAttributes>.activities {
            if tasks.isEmpty {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }

        guard !tasks.isEmpty, Activity<IntervalFocusActivityAttributes>.activities.isEmpty else { return }
        _ = try? Activity.request(
            attributes: IntervalFocusActivityAttributes(),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }
}
#endif
