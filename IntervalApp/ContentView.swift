import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \TaskItem.order) private var allTasks: [TaskItem]
    
    @StateObject private var migrationManager = MigrationManager()
    
    @State private var isCompletedExpanded = false
    @State private var isDeletedExpanded = false
    @FocusState private var focusedTaskId: String?
    
    let intervals = [
        ("1 Hour", 45.0),
        ("1 Day", 30.0),
        ("1 Week", 20.0),
        ("1 Month", 14.0),
        ("1 Year", 11.0)
    ]
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 40) {
                    ForEach(intervals, id: \.0) { interval in
                        TaskListView(
                            title: interval.0,
                            fontSize: interval.1,
                            tasks: allTasks.filter { $0.intervalType == interval.0 && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order },
                            focusedTaskId: $focusedTaskId
                        )
                    }
                    
                    // Bin and Completed Lists
                    VStack(alignment: .leading, spacing: 20) {
                        let completedTasks = allTasks.filter { $0.completed && $0.deletedAt == nil }
                        if !completedTasks.isEmpty {
                            DisclosureGroup(isExpanded: $isCompletedExpanded) {
                                VStack(alignment: .leading, spacing: 15) {
                                    ForEach(completedTasks) { task in
                                        BinRowView(task: task, fontSize: 14.0)
                                    }
                                }
                                .padding(.top, 10)
                                .padding(.leading, 5)
                            } label: {
                                Text("COMPLETED (30 DAYS)")
                                    .font(.system(size: 10, weight: .light, design: .default))
                                    .tracking(2.0)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        let deletedTasks = allTasks.filter { $0.deletedAt != nil }
                        if !deletedTasks.isEmpty {
                            DisclosureGroup(isExpanded: $isDeletedExpanded) {
                                VStack(alignment: .leading, spacing: 15) {
                                    ForEach(deletedTasks) { task in
                                        BinRowView(task: task, fontSize: 14.0)
                                    }
                                }
                                .padding(.top, 10)
                                .padding(.leading, 5)
                            } label: {
                                Text("RECENTLY DELETED")
                                    .font(.system(size: 10, weight: .light, design: .default))
                                    .tracking(2.0)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(40)
            }
            
            if let migration = migrationManager.currentMigration {
                MigrationModalView(
                    migration: migration,
                    tasks: allTasks.filter { $0.intervalType == migration.source && !$0.completed },
                    onMigrate: { selectedTaskIds in
                        migrationManager.executeMigration(
                            migration: migration,
                            selectedTaskIds: selectedTaskIds,
                            allTasks: allTasks,
                            context: modelContext
                        )
                    },
                    onSkip: {
                        migrationManager.skipMigration()
                    }
                )
            }
        }
        .onAppear {
            migrationManager.checkMigrations()
            cleanupOldTasks()
        }
    }
    
    private func cleanupOldTasks() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        for task in allTasks {
            if let deletedAt = task.deletedAt, deletedAt < thirtyDaysAgo {
                modelContext.delete(task)
            } else if let completedAt = task.completedAt, completedAt < thirtyDaysAgo {
                modelContext.delete(task)
            }
        }
    }
}
