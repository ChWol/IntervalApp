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
    case intervalBackup = "Interval"
    case genericCSV = "CSV / JSON"
    
    public var id: String { rawValue }
    
    public var exportInstructions: [String] {
        switch self {
        case .intervalBackup:
            return [
                "Open Interval Settings ⚙️ → Data & Import.",
                "Click 'Export Data (JSON Backup)' to save a complete backup of all your tasks and scratchpads.",
                "Drop the generated .json file here anytime to restore or import your data."
            ]
        case .tickTick:
            return [
                "Open TickTick on the Web (ticktick.com) — not available in mobile/desktop apps.",
                "Click your Profile Avatar (top-left) → Settings ⚙️ → Account → Backup & Restore.",
                "Click 'Generate Backup' to download your CSV file and drag it here."
            ]
        case .microsoftToDo:
            return [
                "Open Outlook / Microsoft To Do on the Web (outlook.live.com).",
                "Go to Settings ⚙️ → General → Privacy and data → Export mailbox.",
                "Or copy/save your list items into a CSV/JSON file and drop it here."
            ]
        case .todoist:
            return [
                "Open Todoist on Web or Desktop (todoist.com).",
                "Click your Profile Avatar (top-left) → Settings ⚙️ → Backups.",
                "Download your latest backup (.zip / .csv) and drag the tasks CSV file here."
            ]
        case .appleReminders:
            return [
                "Open Apple Reminders on your Mac.",
                "Select a list from the sidebar → File → Export... (saves a .ics calendar file).",
                "Or select tasks (⌘A), copy and paste into a text file, and drop it here."
            ]
        case .genericCSV:
            return [
                "Export tasks from Excel, Numbers, Sheets or any tool into a .csv, .tsv, or .json file.",
                "Ensure columns include task titles/names and optional due dates.",
                "Drop the file here to review and categorize into intervals."
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
        
        // 1. Locate the true header row (skipping metadata preambles like TickTick's Version/Status blocks)
        var headerRowIndex: Int? = nil
        for (idx, row) in rows.enumerated().prefix(25) {
            let lower = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let matches = ["title", "task name", "content", "name", "subject", "summary", "folder name", "list name", "due date", "status", "taskid"]
                .filter { candidate in lower.contains(where: { $0.contains(candidate) }) }
            if matches.count >= 2 || (matches.count >= 1 && row.count >= 3) {
                headerRowIndex = idx
                break
            }
        }
        
        let hIdx = headerRowIndex ?? 0
        let header = rows[hIdx].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let source = detectSource(header: header)
        
        // 2. Find Column Indices
        let titleIdx = findIndex(in: header, candidates: ["title", "task name", "task", "name", "summary", "subject"]) ?? 0
        let contentIdx = findIndex(in: header, candidates: ["content", "description", "note", "notes", "memo"])
        let listIdx = findIndex(in: header, candidates: ["list name", "folder name", "list", "project", "folder", "category"])
        let dueIdx = findIndex(in: header, candidates: ["due date", "due time", "due", "date", "start time"])
        let statusIdx = findIndex(in: header, candidates: ["status", "completed", "done", "is_completed"])
        let taskIdIdx = findIndex(in: header, candidates: ["taskid", "task_id", "id"])
        let parentIdIdx = findIndex(in: header, candidates: ["parentid", "parent_id", "parent"])
        
        let defaultLists = Set(["inbox", "tasks", "aufgaben", "general", "to do", "todo", "default", "my tasks", "meine aufgaben"])
        let now = Date()
        
        struct RawItem {
            let taskId: String
            let parentId: String
            var title: String
            var content: String
            let listName: String
            let dueDate: Date?
            let isCompleted: Bool
            var inlineSubtasks: [String]
            var childSubtasks: [String] = []
            var isMergedIntoParent: Bool = false
        }
        
        var rawItems: [RawItem] = []
        var taskIdMap: [String: Int] = [:]
        
        // 3. First pass: Collect all valid data rows
        for r in rows.dropFirst(hIdx + 1) {
            guard r.count > titleIdx else { continue }
            let rawTitle = r[titleIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawContent = (contentIdx != nil && r.count > contentIdx!) ? r[contentIdx!].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            
            // Skip pure divider lines (e.g. "--------", "__________")
            let isDivider = rawTitle.allSatisfy { $0 == "-" || $0 == "_" || $0 == "=" || $0 == " " }
            if isDivider && rawContent.isEmpty { continue }
            if rawTitle.isEmpty && rawContent.isEmpty { continue }
            
            let listName = (listIdx != nil && r.count > listIdx!) ? r[listIdx!].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let rawDue = (dueIdx != nil && r.count > dueIdx!) ? r[dueIdx!].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let rawStatus = (statusIdx != nil && r.count > statusIdx!) ? r[statusIdx!].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : ""
            let taskId = (taskIdIdx != nil && r.count > taskIdIdx!) ? r[taskIdIdx!].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let parentId = (parentIdIdx != nil && r.count > parentIdIdx!) ? r[parentIdIdx!].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            
            // In TickTick: 0 = Normal, 2 = Completed, -1 = Abandoned
            let isCompleted = rawStatus == "2" || rawStatus == "1" || rawStatus == "true" || rawStatus == "completed" || rawStatus == "done" || rawStatus == "yes" || rawStatus == "x"
            let isAbandoned = rawStatus == "-1" || rawStatus == "abandoned" || rawStatus == "cancelled" || rawStatus == "canceled"
            if isAbandoned { continue }
            
            let dueDate = parseDate(from: rawDue)
            let inlineSubtasks = extractSubtasksFromContent(rawContent)
            
            let itemIdx = rawItems.count
            rawItems.append(RawItem(
                taskId: taskId,
                parentId: parentId,
                title: rawTitle,
                content: rawContent,
                listName: listName,
                dueDate: dueDate,
                isCompleted: isCompleted,
                inlineSubtasks: inlineSubtasks
            ))
            if !taskId.isEmpty {
                taskIdMap[taskId] = itemIdx
            }
        }
        
        // 4. Second pass: Resolve Parent-Child relationships
        for i in 0..<rawItems.count {
            let parentId = rawItems[i].parentId
            if !parentId.isEmpty, let parentIdx = taskIdMap[parentId], parentIdx != i {
                let childTitle = rawItems[i].title
                let childSubs = rawItems[i].inlineSubtasks
                let combinedChild = combineTitleWithSubtasks(title: childTitle, subtasks: childSubs)
                if !combinedChild.isEmpty {
                    rawItems[parentIdx].childSubtasks.append(combinedChild)
                }
                rawItems[i].isMergedIntoParent = true
            }
        }
        
        // 5. Third pass: Build Interval Tasks & Scratchpad Lists
        var intervalTasks: [ImportedTask] = []
        var scratchpadMap: [String: [ImportedScratchpadItem]] = [:]
        
        for item in rawItems where !item.isMergedIntoParent {
            let allSubtasks = item.inlineSubtasks + item.childSubtasks
            let finalTitle = combineTitleWithSubtasks(title: item.title, subtasks: allSubtasks)
            guard !finalTitle.isEmpty else { continue }
            
            let isDefaultList = item.listName.isEmpty || defaultLists.contains(item.listName.lowercased())
            if !isDefaultList {
                // Route to Scratchpad List
                var items = scratchpadMap[item.listName] ?? []
                items.append(ImportedScratchpadItem(text: finalTitle, isCompleted: item.isCompleted))
                scratchpadMap[item.listName] = items
            } else {
                // Only active (uncompleted) tasks are routed into active interval columns
                if !item.isCompleted {
                    let interval = assignInterval(for: item.dueDate, now: now)
                    intervalTasks.append(ImportedTask(
                        text: finalTitle,
                        targetInterval: interval,
                        originalListName: item.listName,
                        dueDate: item.dueDate,
                        isCompleted: item.isCompleted
                    ))
                }
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
    
    // MARK: - Subtask Extraction & Combination Helpers
    
    public func extractSubtasksFromContent(_ content: String) -> [String] {
        let lines = content.components(separatedBy: CharacterSet.newlines)
        var subitems: [String] = []
        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            // Remove checklist/bullet point prefixes
            let prefixes = ["▪", "▫", "•", "✓", "✔", "- [ ]", "- [x]", "- [X]", "[ ]", "[x]", "[X]", "*", "-", "—"]
            for p in prefixes {
                if trimmed.hasPrefix(p) {
                    trimmed = String(trimmed.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            // Remove numbered prefixes e.g. "1.", "2)"
            if let match = trimmed.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                trimmed = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            // Remove trailing arrows
            if trimmed.hasSuffix("->") {
                trimmed = String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces)
            }
            
            if !trimmed.isEmpty {
                subitems.append(trimmed)
            }
        }
        return subitems
    }
    
    public func combineTitleWithSubtasks(title: String, subtasks: [String]) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSubtasks = subtasks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if cleanSubtasks.isEmpty {
            return cleanTitle
        }
        
        let subtaskStr = cleanSubtasks.joined(separator: ", ")
        if cleanTitle.isEmpty {
            return subtaskStr
        } else if cleanTitle.hasSuffix(":") {
            return "\(cleanTitle) \(subtaskStr)"
        } else {
            return "\(cleanTitle): \(subtaskStr)"
        }
    }
    
    private func parseJSON(data: Data) throws -> ImportAnalysis {
        // 1. Check if this is an Interval Backup JSON
        if let backup = try? JSONDecoder().decode(IntervalBackupDTO.self, from: data), backup.format == "Interval_Backup" {
            var intervalTasks: [ImportedTask] = []
            for t in backup.tasks where t.deletedAt == nil {
                intervalTasks.append(ImportedTask(
                    id: t.id,
                    text: t.text,
                    targetInterval: t.intervalType,
                    originalListName: "Interval Backup",
                    dueDate: nil,
                    isCompleted: t.completed
                ))
            }
            
            var scratchpadLists: [ImportedScratchpadList] = []
            let activeItems = backup.scratchpadItems.filter { $0.deletedAt == nil }
            for l in backup.scratchpadLists where l.deletedAt == nil {
                let listItems = activeItems.filter { $0.listId == l.id }.map {
                    ImportedScratchpadItem(id: $0.id, text: $0.text, isCompleted: $0.completed)
                }
                scratchpadLists.append(ImportedScratchpadList(
                    id: l.id,
                    title: l.title,
                    items: listItems
                ))
            }
            
            return ImportAnalysis(intervalTasks: intervalTasks, scratchpadLists: scratchpadLists, detectedSource: .intervalBackup)
        }
        
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
