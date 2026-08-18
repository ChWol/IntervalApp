import Foundation
import SwiftData
import SwiftUI

// MARK: - Import Data Structures

public struct ImportedTask: Identifiable, Hashable {
    public let id: String
    public var text: String
    public var targetInterval: String // "1 Day", "1 Week", "1 Month", "1 Year"
    public var originalListName: String
    public var dueDate: Date?
    public var isCompleted: Bool
    public var isSelected: Bool
    
    public init(
        id: String = UUID().uuidString,
        text: String,
        targetInterval: String,
        originalListName: String = "",
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        isSelected: Bool = true
    ) {
        self.id = id
        self.text = text
        self.targetInterval = targetInterval
        self.originalListName = originalListName
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.isSelected = isSelected
    }
}

public struct ImportedScratchpadList: Identifiable, Hashable {
    public let id: String
    public var title: String
    public var items: [ImportedScratchpadItem]
    public var isSelected: Bool
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        items: [ImportedScratchpadItem] = [],
        isSelected: Bool = true
    ) {
        self.id = id
        self.title = title
        self.items = items
        self.isSelected = isSelected
    }
}

public struct ImportedScratchpadItem: Identifiable, Hashable {
    public let id: String
    public var text: String
    public var isCompleted: Bool
    
    public init(id: String = UUID().uuidString, text: String, isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
    }
}

public struct ImportAnalysis {
    public var intervalTasks: [ImportedTask]
    public var scratchpadLists: [ImportedScratchpadList]
    public var detectedSource: ImportSource
    public var totalCount: Int {
        intervalTasks.count + scratchpadLists.reduce(0) { $0 + $1.items.count }
    }
}

public enum ImportSource: String, CaseIterable, Identifiable {
    case tickTick = "TickTick"
    case microsoftToDo = "Microsoft To Do"
    case todoist = "Todoist"
    case appleReminders = "Apple Reminders"
    case genericCSV = "CSV / JSON"
    
    public var id: String { rawValue }
    
    public var exportInstructions: [String] {
        switch self {
        case .tickTick:
            return [
                "Open TickTick on Web or Desktop (ticktick.com)",
                "Go to Settings ⚙️ → Backup → Export Backup",
                "Download the CSV file and drag it here."
            ]
        case .microsoftToDo:
            return [
                "Open Outlook / Microsoft To Do on the Web",
                "Go to Settings ⚙️ → General → Privacy and data → Export mailbox / tasks",
                "Or export your lists to CSV/JSON and drop the file here."
            ]
        case .todoist:
            return [
                "Open Todoist Settings ⚙️ → Backups",
                "Download your latest backup (.zip / .csv)",
                "Extract and drag the tasks CSV file here."
            ]
        case .appleReminders:
            return [
                "Open Apple Reminders on your Mac",
                "Select a list → File → Export... (or drag & drop tasks)",
                "Drop the exported .ics or text list file here."
            ]
        case .genericCSV:
            return [
                "Export tasks from any tool into a CSV, TSV or JSON file",
                "Make sure it includes task titles/names and optional due dates",
                "Drop the file here to review and categorize."
            ]
        }
    }
}

// MARK: - Import Manager

public final class ImportManager: Sendable {
    public static let shared = ImportManager()
    
    private init() {}
    
    // MARK: - Parsing Engine
    
    public func parseFile(at url: URL) throws -> ImportAnalysis {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "ImportManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read file encoding."])
        }
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.starts(with: "{") || trimmed.starts(with: "[") {
            return try parseJSON(data: data)
        } else if trimmed.contains("BEGIN:VCALENDAR") || trimmed.contains("BEGIN:VTODO") {
            return parseICS(text: text)
        } else {
            return parseCSV(text: text)
        }
    }
    
    // MARK: - CSV Parsing
    
    public func parseCSV(text: String) -> ImportAnalysis {
        let rows = parseCSVRows(text: text)
        guard !rows.isEmpty else {
            return ImportAnalysis(intervalTasks: [], scratchpadLists: [], detectedSource: .genericCSV)
        }
        
        let header = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let source = detectSource(header: header)
        
        var intervalTasks: [ImportedTask] = []
        var scratchpadMap: [String: [ImportedScratchpadItem]] = [:]
        
        // Find Column Indices
        let titleIdx = findIndex(in: header, candidates: ["title", "task name", "content", "task", "name", "summary", "description"]) ?? 0
        let listIdx = findIndex(in: header, candidates: ["list name", "folder name", "list", "project", "folder", "category"])
        let dueIdx = findIndex(in: header, candidates: ["due date", "due time", "due", "date", "start time"])
        let statusIdx = findIndex(in: header, candidates: ["status", "completed", "done", "is_completed"])
        
        let defaultLists = Set(["inbox", "tasks", "aufgaben", "general", "to do", "todo", "default", "my tasks", "meine aufgaben"])
        
        let now = Date()
        
        for r in rows.dropFirst() {
            guard r.count > titleIdx else { continue }
            let rawTitle = r[titleIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawTitle.isEmpty else { continue }
            
            let listName = (listIdx != nil && r.count > listIdx!) ? r[listIdx!].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let rawDue = (dueIdx != nil && r.count > dueIdx!) ? r[dueIdx!].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let rawStatus = (statusIdx != nil && r.count > statusIdx!) ? r[statusIdx!].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : ""
            
            let isCompleted = rawStatus == "1" || rawStatus == "true" || rawStatus == "completed" || rawStatus == "done" || rawStatus == "yes" || rawStatus == "x"
            let dueDate = parseDate(from: rawDue)
            
            let isDefaultList = listName.isEmpty || defaultLists.contains(listName.lowercased())
            
            if !isDefaultList {
                // Route to Scratchpad List
                var items = scratchpadMap[listName] ?? []
                items.append(ImportedScratchpadItem(text: rawTitle, isCompleted: isCompleted))
                scratchpadMap[listName] = items
            } else {
                // Route to Interval Task based on due date
                let interval = assignInterval(for: dueDate, now: now)
                intervalTasks.append(ImportedTask(
                    text: rawTitle,
                    targetInterval: interval,
                    originalListName: listName,
                    dueDate: dueDate,
                    isCompleted: isCompleted
                ))
            }
        }
        
        let scratchpadLists = scratchpadMap.map { name, items in
            ImportedScratchpadList(title: name, items: items)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        
        return ImportAnalysis(
            intervalTasks: intervalTasks,
            scratchpadLists: scratchpadLists,
            detectedSource: source
        )
    }
    
    // MARK: - JSON Parsing
    
    private func parseJSON(data: Data) throws -> ImportAnalysis {
        var intervalTasks: [ImportedTask] = []
        var scratchpadMap: [String: [ImportedScratchpadItem]] = [:]
        let now = Date()
        
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for obj in jsonArray {
                let title = (obj["title"] ?? obj["task"] ?? obj["name"] ?? obj["content"] ?? "") as? String ?? ""
                guard !title.isEmpty else { continue }
                let listName = (obj["list"] ?? obj["listName"] ?? obj["folder"] ?? obj["project"] ?? "") as? String ?? ""
                let rawDue = (obj["dueDate"] ?? obj["due"] ?? obj["date"] ?? "") as? String ?? ""
                let isCompleted = (obj["completed"] ?? obj["isCompleted"] ?? obj["done"] ?? false) as? Bool ?? false
                let dueDate = parseDate(from: rawDue)
                
                let defaultLists = Set(["inbox", "tasks", "aufgaben", "general", "to do", "todo", "default", "my tasks"])
                if !listName.isEmpty && !defaultLists.contains(listName.lowercased()) {
                    var items = scratchpadMap[listName] ?? []
                    items.append(ImportedScratchpadItem(text: title, isCompleted: isCompleted))
                    scratchpadMap[listName] = items
                } else {
                    let interval = assignInterval(for: dueDate, now: now)
                    intervalTasks.append(ImportedTask(
                        text: title,
                        targetInterval: interval,
                        originalListName: listName,
                        dueDate: dueDate,
                        isCompleted: isCompleted
                    ))
                }
            }
        }
        
        let scratchpadLists = scratchpadMap.map { name, items in
            ImportedScratchpadList(title: name, items: items)
        }
        
        return ImportAnalysis(intervalTasks: intervalTasks, scratchpadLists: scratchpadLists, detectedSource: .genericCSV)
    }
    
    // MARK: - ICS Parsing (Apple Reminders / iCalendar)
    
    private func parseICS(text: String) -> ImportAnalysis {
        var intervalTasks: [ImportedTask] = []
        var currentSummary: String?
        var currentDue: Date?
        var isCompleted = false
        let now = Date()
        
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "BEGIN:VTODO") {
                currentSummary = nil
                currentDue = nil
                isCompleted = false
            } else if trimmed.starts(with: "SUMMARY:") {
                currentSummary = String(trimmed.dropFirst(8))
            } else if trimmed.starts(with: "DUE") || trimmed.starts(with: "DTSTART") {
                if let colon = trimmed.firstIndex(of: ":") {
                    let dateStr = String(trimmed[trimmed.index(after: colon)...])
                    currentDue = parseDate(from: dateStr)
                }
            } else if trimmed.starts(with: "STATUS:COMPLETED") {
                isCompleted = true
            } else if trimmed.starts(with: "END:VTODO") {
                if let summary = currentSummary, !summary.isEmpty {
                    let interval = assignInterval(for: currentDue, now: now)
                    intervalTasks.append(ImportedTask(
                        text: summary,
                        targetInterval: interval,
                        originalListName: "Apple Reminders",
                        dueDate: currentDue,
                        isCompleted: isCompleted
                    ))
                }
            }
        }
        
        return ImportAnalysis(intervalTasks: intervalTasks, scratchpadLists: [], detectedSource: .appleReminders)
    }
    
    // MARK: - Intelligent Interval Mapping
    
    public func assignInterval(for dueDate: Date?, now: Date = Date()) -> String {
        guard let due = dueDate else {
            return "1 Week" // Default horizon for unscheduled inbox tasks
        }
        
        let calendar = Calendar.current
        
        // 1. Due Today or Overdue -> 1 Day
        if due <= now || calendar.isDateInToday(due) {
            return "1 Day"
        }
        
        // 2. Due within 7 days -> 1 Week
        if let weekLimit = calendar.date(byAdding: .day, value: 7, to: now), due <= weekLimit {
            return "1 Week"
        }
        
        // 3. Due within 30 days -> 1 Month
        if let monthLimit = calendar.date(byAdding: .day, value: 30, to: now), due <= monthLimit {
            return "1 Month"
        }
        
        // 4. Later in the year -> 1 Year
        return "1 Year"
    }
    
    // MARK: - Commit Import into SwiftData & Sync
    
    @MainActor
    public func commitImport(
        tasks: [ImportedTask],
        scratchpadLists: [ImportedScratchpadList],
        context: ModelContext
    ) {
        let now = Date()
        
        // 1. Insert Interval Tasks
        let existingTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        var maxOrder = (existingTasks.map { $0.order }.max() ?? -1) + 1
        
        for task in tasks where task.isSelected && !task.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let taskItem = TaskItem(
                text: task.text.trimmingCharacters(in: .whitespaces),
                intervalType: task.targetInterval,
                order: maxOrder
            )
            taskItem.completed = task.isCompleted
            taskItem.completedAt = task.isCompleted ? now : nil
            taskItem.createdAt = now
            taskItem.updatedAt = now
            context.insert(taskItem)
            maxOrder += 1
        }
        
        // 2. Insert Scratchpad Lists & Items
        let existingLists = (try? context.fetch(FetchDescriptor<ScratchpadList>())) ?? []
        var maxListOrder = (existingLists.map { $0.order }.max() ?? -1) + 1
        
        for list in scratchpadLists where list.isSelected && !list.items.isEmpty {
            let newList = ScratchpadList(title: list.title.trimmingCharacters(in: .whitespaces), order: maxListOrder)
            newList.createdAt = now
            newList.updatedAt = now
            context.insert(newList)
            maxListOrder += 1
            
            var itemOrder = 0
            for item in list.items where !item.text.trimmingCharacters(in: .whitespaces).isEmpty {
                let newItem = ScratchpadItem(
                    listId: newList.id,
                    text: item.text.trimmingCharacters(in: .whitespaces),
                    order: itemOrder
                )
                newItem.completed = item.isCompleted
                newItem.completedAt = item.isCompleted ? now : nil
                newItem.createdAt = now
                newItem.updatedAt = now
                context.insert(newItem)
                itemOrder += 1
            }
        }
        
        try? context.save()
        SoundManager.playTransitionChime()
        SupabaseSyncManager.shared.push()
    }
    
    // MARK: - Helper Methods
    
    private func parseCSVRows(text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        let delimiter: Character = detectDelimiter(text: text)
        
        var iterator = text.makeIterator()
        while let char = iterator.next() {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == delimiter && !insideQuotes {
                currentRow.append(currentField)
                currentField = ""
            } else if (char == "\r" || char == "\n") && !insideQuotes {
                if char == "\r" {
                    // Check if next is \n
                    // Ignored in standard iterator
                }
                currentRow.append(currentField)
                if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(currentRow)
            }
        }
        
        return rows
    }
    
    private func detectDelimiter(text: String) -> Character {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let commas = firstLine.filter { $0 == "," }.count
        let semicolons = firstLine.filter { $0 == ";" }.count
        let tabs = firstLine.filter { $0 == "\t" }.count
        
        if tabs > commas && tabs > semicolons { return "\t" }
        if semicolons > commas { return ";" }
        return ","
    }
    
    private func detectSource(header: [String]) -> ImportSource {
        let h = header.joined(separator: " ")
        if h.contains("folder name") && h.contains("due time") { return .tickTick }
        if h.contains("importance") || (h.contains("task name") && h.contains("due date")) { return .microsoftToDo }
        if h.contains("indent") && h.contains("responsible") { return .todoist }
        return .genericCSV
    }
    
    private func findIndex(in headers: [String], candidates: [String]) -> Int? {
        for candidate in candidates {
            if let idx = headers.firstIndex(where: { $0.contains(candidate) }) {
                return idx
            }
        }
        return nil
    }
    
    private func parseDate(from string: String) -> Date? {
        let str = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy",
            "dd.MM.yyyy HH:mm",
            "dd.MM.yyyy",
            "yyyyMMdd'T'HHmmss'Z'",
            "yyyyMMdd"
        ]
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: str) {
                return date
            }
        }
        return nil
    }
}
