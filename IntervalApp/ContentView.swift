import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \TaskItem.order) private var allTasks: [TaskItem]
    
    @StateObject private var migrationManager = MigrationManager()
    @ObservedObject private var dragState = DragState.shared
    
    @State private var isCompletedExpanded = false
    @State private var isDeletedExpanded = false
    @State private var showAllCompleted = false
    @State private var showAllDeleted = false
    @State private var focusedTaskId: String?
    
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
                        let completedTasks = allTasks.filter { $0.completed && $0.deletedAt == nil }.sorted { ($0.completedAt ?? Date()) > ($1.completedAt ?? Date()) }
                        if !completedTasks.isEmpty {
                            DisclosureGroup(isExpanded: $isCompletedExpanded) {
                                VStack(alignment: .leading, spacing: 15) {
                                    let displayed = showAllCompleted ? completedTasks : Array(completedTasks.prefix(10))
                                    ForEach(displayed) { task in
                                        BinRowView(task: task, fontSize: 14.0)
                                    }
                                    HStack {
                                        if completedTasks.count > 10 {
                                            Button(action: { withAnimation { showAllCompleted.toggle() } }) {
                                                Text(showAllCompleted ? "Show Less" : "Show More (\(completedTasks.count - 10))")
                                                    .font(.system(size: 12, weight: .light))
                                                    .foregroundColor(.gray)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            withAnimation {
                                                clearCompletedTasks()
                                            }
                                        }) {
                                            Text("Clear All")
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundColor(.gray)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.top, 5)
                                }
                                .padding(.top, 10)
                                .padding(.leading, 5)
                            } label: {
                                Text("COMPLETED")
                                    .font(.system(size: 10, weight: .light, design: .default))
                                    .tracking(2.0)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation { isCompletedExpanded.toggle() }
                                    }
                            }
                            .onChange(of: isCompletedExpanded) { _, newValue in
                                if !newValue { showAllCompleted = false }
                            }
                        }
                        
                        let deletedTasks = allTasks.filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? Date()) > ($1.deletedAt ?? Date()) }
                        if !deletedTasks.isEmpty {
                            DisclosureGroup(isExpanded: $isDeletedExpanded) {
                                VStack(alignment: .leading, spacing: 15) {
                                    let displayed = showAllDeleted ? deletedTasks : Array(deletedTasks.prefix(10))
                                    ForEach(displayed) { task in
                                        BinRowView(task: task, fontSize: 14.0)
                                    }
                                    HStack {
                                        if deletedTasks.count > 10 {
                                            Button(action: { withAnimation { showAllDeleted.toggle() } }) {
                                                Text(showAllDeleted ? "Show Less" : "Show More (\(deletedTasks.count - 10))")
                                                    .font(.system(size: 12, weight: .light))
                                                    .foregroundColor(.gray)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            withAnimation {
                                                clearDeletedTasks()
                                            }
                                        }) {
                                            Text("Clear All")
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundColor(.gray)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.top, 5)
                                }
                                .padding(.top, 10)
                                .padding(.leading, 5)
                            } label: {
                                Text("RECENTLY DELETED")
                                    .font(.system(size: 10, weight: .light, design: .default))
                                    .tracking(2.0)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation { isDeletedExpanded.toggle() }
                                    }
                            }
                            .onChange(of: isDeletedExpanded) { _, newValue in
                                if !newValue { showAllDeleted = false }
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
                    tasks: allTasks.filter { $0.intervalType == migration.source && !$0.completed && $0.deletedAt == nil },
                    onMigrate: { selectedTaskIds in
                        migrationManager.executeMigration(
                            migration: migration,
                            selectedTaskIds: selectedTaskIds,
                            allTasks: allTasks,
                            context: modelContext
                        )
                    },
                    onCommitGoals: { goals in
                        let yearTasks = allTasks.filter { $0.intervalType == "1 Year" && !$0.completed && $0.deletedAt == nil }
                        var maxOrder = (yearTasks.map { $0.order }.max() ?? -1) + 1
                        for goal in goals {
                            let newTask = TaskItem(text: goal, intervalType: "1 Year", order: maxOrder)
                            modelContext.insert(newTask)
                            maxOrder += 1
                        }
                        try? modelContext.save()
                        migrationManager.currentMigration = nil
                    },
                    onSkip: {
                        migrationManager.skipMigration()
                    }
                )
            }
            
            // Simulation Toolbar
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Text("SIMULATE:")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(1)
                    
                    Group {
                        Button("Hour") {
                            migrationManager.triggerSimulatedMigration(source: "1 Day", dest: "1 Hour")
                        }
                        Button("Day") {
                            migrationManager.triggerSimulatedMigration(source: "1 Week", dest: "1 Day")
                        }
                        Button("Week") {
                            migrationManager.triggerSimulatedMigration(source: "1 Month", dest: "1 Week")
                        }
                        Button("Month") {
                            migrationManager.triggerSimulatedMigration(source: "1 Year", dest: "1 Month")
                        }
                        Button("Year") {
                            migrationManager.triggerSimulatedMigration(source: "1 Year", dest: "1 Year")
                        }
                    }
                    .font(.system(size: 11, weight: .light))
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                )
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            migrationManager.checkMigrations()
            cleanupOldTasks()
        }
    }
    
    private func clearCompletedTasks() {
        let completedTasks = allTasks.filter { $0.completed && $0.deletedAt == nil }
        for task in completedTasks {
            modelContext.delete(task)
        }
    }
    
    private func clearDeletedTasks() {
        let deletedTasks = allTasks.filter { $0.deletedAt != nil }
        for task in deletedTasks {
            modelContext.delete(task)
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
