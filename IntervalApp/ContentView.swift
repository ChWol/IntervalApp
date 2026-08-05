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
                                    if completedTasks.count > 10 {
                                        Button(action: { withAnimation { showAllCompleted.toggle() } }) {
                                            Text(showAllCompleted ? "Show Less" : "Show More (\(completedTasks.count - 10))")
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundColor(.gray)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 5)
                                    }
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
                                    if deletedTasks.count > 10 {
                                        Button(action: { withAnimation { showAllDeleted.toggle() } }) {
                                            Text(showAllDeleted ? "Show Less" : "Show More (\(deletedTasks.count - 10))")
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundColor(.gray)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 5)
                                    }
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
            
            // Floating Drag Overlay (Custom live SwiftUI drag preview that morphs size across sections)
            if let draggedTask = dragState.draggedTask {
                let activeFontSize = dragState.targetFontSize
                HStack(spacing: 12) {
                    Text("–")
                        .font(.system(size: activeFontSize * 0.8, weight: .light))
                        .foregroundColor(.secondary)
                    Text(draggedTask.text)
                        .font(.system(size: activeFontSize, weight: .light))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, max(8, activeFontSize * 0.4))
                .padding(.vertical, max(4, activeFontSize * 0.2))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                )
                .position(dragState.dragPosition)
                .allowsHitTesting(false)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: dragState.targetFontSize)
                .transition(.opacity)
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
