import Foundation
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// MARK: - Export Data Transfer Objects

struct IntervalBackupDTO: Codable {
    let version: String
    let format: String
    let exportedAt: String
    let tasks: [TaskBackupDTO]
    let habits: [HabitBackupDTO]
    let scratchpadLists: [ScratchpadListBackupDTO]
    let scratchpadItems: [ScratchpadItemBackupDTO]
}

struct TaskBackupDTO: Codable {
    let id: String
    let text: String
    let intervalType: String
    let order: Int
    let completed: Bool
    let habitId: String?
    let createdAt: String?
    let updatedAt: String?
    let completedAt: String?
    let deletedAt: String?
}

struct HabitBackupDTO: Codable {
    let id: String
    let text: String
    let frequency: String
    let streak: Int
    let order: Int
    let lastCompletedDate: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct ScratchpadListBackupDTO: Codable {
    let id: String
    let title: String
    let order: Int
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct ScratchpadItemBackupDTO: Codable {
    let id: String
    let listId: String
    let text: String
    let order: Int
    let completed: Bool
    let createdAt: String?
    let updatedAt: String?
    let completedAt: String?
    let deletedAt: String?
}

// MARK: - Export Manager

@MainActor
final class ExportManager {
    static let shared = ExportManager()
    
    private static let isoFormatter = ISO8601DateFormatter()
    
    private init() {}
    
    /// Generates full structured JSON backup data from local SwiftData context
    func generateBackupData(context: ModelContext) -> Data? {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<HabitItem>())) ?? []
        let lists = (try? context.fetch(FetchDescriptor<ScratchpadList>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<ScratchpadItem>())) ?? []
        
        let taskDTOs = tasks.map { t in
            TaskBackupDTO(
                id: t.id,
                text: t.text,
                intervalType: t.intervalType,
                order: t.order,
                completed: t.completed,
                habitId: t.habitId,
                createdAt: Self.isoFormatter.string(from: t.createdAt),
                updatedAt: Self.isoFormatter.string(from: t.updatedAt),
                completedAt: t.completedAt.map { Self.isoFormatter.string(from: $0) },
                deletedAt: t.deletedAt.map { Self.isoFormatter.string(from: $0) }
            )
        }
        
        let habitDTOs = habits.map { h in
            HabitBackupDTO(
                id: h.id,
                text: h.text,
                frequency: h.frequency,
                streak: h.streak,
                order: h.order,
                lastCompletedDate: h.lastCompletedDate.map { Self.isoFormatter.string(from: $0) },
                updatedAt: Self.isoFormatter.string(from: h.updatedAt),
                deletedAt: h.deletedAt.map { Self.isoFormatter.string(from: $0) }
            )
        }
        
        let listDTOs = lists.map { l in
            ScratchpadListBackupDTO(
                id: l.id,
                title: l.title,
                order: l.order,
                createdAt: Self.isoFormatter.string(from: l.createdAt),
                updatedAt: Self.isoFormatter.string(from: l.updatedAt),
                deletedAt: l.deletedAt.map { Self.isoFormatter.string(from: $0) }
            )
        }
        
        let itemDTOs = items.map { i in
            ScratchpadItemBackupDTO(
                id: i.id,
                listId: i.listId,
                text: i.text,
                order: i.order,
                completed: i.completed,
                createdAt: Self.isoFormatter.string(from: i.createdAt),
                updatedAt: Self.isoFormatter.string(from: i.updatedAt),
                completedAt: i.completedAt.map { Self.isoFormatter.string(from: $0) },
                deletedAt: i.deletedAt.map { Self.isoFormatter.string(from: $0) }
            )
        }
        
        let backup = IntervalBackupDTO(
            version: "1.0",
            format: "Interval_Backup",
            exportedAt: Self.isoFormatter.string(from: Date()),
            tasks: taskDTOs,
            habits: habitDTOs,
            scratchpadLists: listDTOs,
            scratchpadItems: itemDTOs
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(backup)
    }
    
    #if os(macOS)
    /// Prompts user with NSSavePanel to save the backup JSON file
    func exportToFile(context: ModelContext) -> Bool {
        guard let data = generateBackupData(context: context) else { return false }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let defaultFileName = "Interval_Backup_\(dateString).json"
        
        let panel = NSSavePanel()
        panel.title = "Export Data (JSON Backup)".localized
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        
        let result = panel.runModal()
        if result == .OK, let targetURL = panel.url {
            do {
                try data.write(to: targetURL)
                return true
            } catch {
                print("Failed to save backup file: \(error)")
                return false
            }
        }
        return false
    }
    #endif
}
