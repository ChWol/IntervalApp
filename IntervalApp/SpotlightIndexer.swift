#if os(iOS) || os(macOS)
@preconcurrency import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

extension Notification.Name {
    static let spotlightOpenItem = Notification.Name("spotlightOpenItem")
}

/// Maintains a private, on-device Spotlight index for the same records visible in
/// the app. Indexing is debounced because text editing can save on every keystroke.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()
    private let index = CSSearchableIndex(name: "Interval")
    private var pendingWork: DispatchWorkItem?

    private init() {}

    func schedule(context: ModelContext) {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.indexNow(context: context)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func indexNow(context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<HabitItem>())) ?? []
        let lists = (try? context.fetch(FetchDescriptor<ScratchpadList>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<ScratchpadItem>())) ?? []

        var searchable: [CSSearchableItem] = []
        searchable += tasks.filter { $0.deletedAt == nil }.map {
            makeItem(id: "task:\($0.id)", title: LinkTaskText.displayText(for: $0.text),
                     description: "\($0.intervalType) task", keywords: [$0.intervalType])
        }
        searchable += habits.filter { $0.deletedAt == nil }.map {
            makeItem(id: "habit:\($0.id)", title: $0.text,
                     description: "Habit · \($0.frequency)", keywords: ["Habit", $0.frequency])
        }
        searchable += lists.filter { $0.deletedAt == nil }.map {
            makeItem(id: "list:\($0.id)", title: $0.title,
                     description: "Scratchpad list", keywords: ["Scratchpad"])
        }
        let listNames = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.title) })
        searchable += items.filter { $0.deletedAt == nil }.map {
            makeItem(id: "scratch:\($0.id)", title: $0.text,
                     description: "Scratchpad · \(listNames[$0.listId] ?? "List")", keywords: ["Scratchpad"])
        }

        index.deleteAllSearchableItems { [weak self] _ in
            guard !searchable.isEmpty else { return }
            self?.index.indexSearchableItems(searchable)
        }
    }

    func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme == "interval", url.host == "spotlight" else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return false }
        // Defer one run-loop turn so a cold-launched scene has mounted its
        // ContentView before the navigation notification is delivered.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .spotlightOpenItem,
                object: nil,
                userInfo: ["kind": parts[0], "id": parts[1]]
            )
        }
        return true
    }

    private func makeItem(id: String, title: String, description: String, keywords: [String]) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
        attributes.title = title
        attributes.contentDescription = description
        attributes.keywords = keywords + title.split(separator: " ").map(String.init)
        attributes.url = URL(string: "interval://spotlight/\(id.replacingOccurrences(of: ":", with: "/"))")
        return CSSearchableItem(uniqueIdentifier: id, domainIdentifier: "chw.IntervalApp", attributeSet: attributes)
    }
}
#endif
