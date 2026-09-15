import Foundation
#if !WIDGET_EXTENSION
import SwiftData
#endif
#if os(iOS) && !WIDGET_EXTENSION
import WidgetKit
#endif

struct WidgetTaskSnapshot: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let order: Int
}

struct WidgetSnapshot: Codable, Equatable {
    let tasks: [WidgetTaskSnapshot]
    let generatedAt: Date
}

enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.chw.IntervalApp"
    private static let filename = "widget-snapshot.json"

    static func read() -> WidgetSnapshot {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(filename),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot(tasks: [], generatedAt: .distantPast)
        }
        return snapshot
    }

#if !WIDGET_EXTENSION
    static func clear() {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(filename) else { return }
        try? FileManager.default.removeItem(at: url)
        #if os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: "IntervalHomeWidget")
        #endif
    }

    @MainActor
    static func write(context: ModelContext) {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.intervalType == "1 Hour" && task.deletedAt == nil && !task.completed
            },
            sortBy: [SortDescriptor(\TaskItem.order)]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        let snapshot = WidgetSnapshot(
            tasks: tasks.map {
                WidgetTaskSnapshot(id: $0.id, title: LinkTaskText.displayText(for: $0.text), order: $0.order)
            },
            generatedAt: Date()
        )
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(filename),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        #if os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: "IntervalHomeWidget")
        #endif
    }
#endif
}
