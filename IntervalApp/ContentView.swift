import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \TaskItem.order) private var allTasks: [TaskItem]
    
    @StateObject private var migrationManager = MigrationManager()
    
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
                            tasks: allTasks.filter { $0.intervalType == interval.0 }.sorted { $0.order < $1.order }
                        )
                    }
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
        }
    }
}
