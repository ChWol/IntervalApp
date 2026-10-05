#if os(iOS) || os(macOS)
@preconcurrency import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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
    private var pendingOpenTarget: (kind: String, id: String)?
    private var lastQueuedOpenKey: String?
    private var lastQueuedOpenDate = Date.distantPast

    private init() {}

    func clear() {
        pendingWork?.cancel()
        pendingWork = nil
        index.deleteAllSearchableItems()
    }

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

        let searchableIndex = index
        searchableIndex.deleteAllSearchableItems { _ in
            guard !searchable.isEmpty else { return }
            searchableIndex.indexSearchableItems(searchable)
        }
    }

    func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme == "interval", url.host == "spotlight" else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return false }
        queueOpenTarget(kind: parts[0], id: parts[1])
        return true
    }

    func handleSearchableItemActivity(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == CSSearchableItemActionType,
              let uniqueIdentifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let separator = uniqueIdentifier.firstIndex(of: ":") else { return false }
        let kind = String(uniqueIdentifier[..<separator])
        let id = String(uniqueIdentifier[uniqueIdentifier.index(after: separator)...])
        guard !kind.isEmpty, !id.isEmpty else { return false }
        queueOpenTarget(kind: kind, id: id)
        return true
    }

    private func queueOpenTarget(kind: String, id: String) {
        let key = "\(kind):\(id)"
        guard lastQueuedOpenKey != key || Date().timeIntervalSince(lastQueuedOpenDate) > 1 else { return }
        lastQueuedOpenKey = key
        lastQueuedOpenDate = Date()
        pendingOpenTarget = (kind, id)
        // Keep the target queued until ContentView consumes it. A one-turn
        // delay alone can still fire before the cold-launched window subscribes.
        DispatchQueue.main.async {
            guard self.pendingOpenTarget?.kind == kind,
                  self.pendingOpenTarget?.id == id else { return }
            NotificationCenter.default.post(
                name: .spotlightOpenItem,
                object: nil,
                userInfo: ["kind": kind, "id": id]
            )
        }
    }

    func consumePendingOpenTarget() -> (kind: String, id: String)? {
        defer { pendingOpenTarget = nil }
        return pendingOpenTarget
    }

    private func makeItem(id: String, title: String, description: String, keywords: [String]) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.content)
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = description
        attributes.keywords = keywords + title.split(separator: " ").map(String.init)
        attributes.url = URL(string: "interval://spotlight/\(id.replacingOccurrences(of: ":", with: "/"))")
#if os(macOS)
        // Core Spotlight otherwise presents these text records with a generic
        // document glyph. Use the installed product's real app icon as its item thumbnail.
        let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        if let tiff = appIcon.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff) {
            attributes.thumbnailData = bitmap.representation(using: .png, properties: [:])
        }
#endif
        // Use the running product's bundle identity so Spotlight associates
        // indexed records with the app that created them (including Debug builds).
        let domainIdentifier = Bundle.main.bundleIdentifier ?? "chw.IntervalApp"
        return CSSearchableItem(uniqueIdentifier: id, domainIdentifier: domainIdentifier, attributeSet: attributes)
    }
}
#endif
