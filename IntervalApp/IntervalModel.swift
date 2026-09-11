import Foundation
import SwiftData

enum LinkTaskText {
    struct Parts {
        let title: String
        let url: URL
    }

    /// Stored link tasks use `Title (https://example.com)` so the URL survives
    /// sync/export while the list can show the useful part of the task.
    static func parts(in text: String) -> Parts? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"),
              let opening = trimmed.range(of: " (", options: .backwards)?.lowerBound,
              opening > trimmed.startIndex else { return nil }

        let title = String(trimmed[..<opening]).trimmingCharacters(in: .whitespacesAndNewlines)
        let urlText = String(trimmed[trimmed.index(opening, offsetBy: 2)..<trimmed.index(before: trimmed.endIndex)])
        guard !title.isEmpty, let url = validURL(urlText) else { return nil }
        return Parts(title: title, url: url)
    }

    static func validURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }

    static func displayText(for text: String) -> String {
        parts(in: text)?.title ?? text
    }

    static func storedText(title: String, url: URL) -> String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines)) (\(url.absoluteString))"
    }

    static func fetchTitle(for url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Interval)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode) else { return nil }

        let html = String(decoding: data, as: UTF8.self)
        guard let match = html.range(of: #"<title(?:\s[^>]*)?>(.*?)</title>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let title = String(html[match])
            .replacingOccurrences(of: #"<title(?:\s[^>]*)?>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</title>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .decodingHTMLEntities()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}

private extension String {
    func decodingHTMLEntities() -> String {
        var result = self
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, value) in entities {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }
}

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
    /// Set when the task was created from a habit during an hourly migration. Completing the
    /// task then also completes that habit, and vice versa.
    var habitId: String? = nil
    var updatedAt: Date = Date()
    /// Value of `updatedAt` at the time the row was last confirmed by the server.
    /// `nil`, or older than `updatedAt`, means the row still has unpublished local changes.
    var syncedAt: Date? = nil

    init(text: String, intervalType: String, order: Int = 0, habitId: String? = nil) {
        self.id = UUID().uuidString
        self.text = text
        self.completed = false
        self.createdAt = Date()
        self.intervalType = intervalType
        self.order = order
        self.deletedAt = nil
        self.completedAt = nil
        self.habitId = habitId
        self.updatedAt = Date()
        self.syncedAt = nil
    }
}
