import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \TaskItem.order) private var allTasks: [TaskItem]
    
    @StateObject private var migrationManager = MigrationManager()
    @StateObject private var syncManager = SupabaseSyncManager.shared
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
        if syncManager.isAuthenticated {
            mainAppView
                .onAppear {
                    syncManager.start(context: modelContext)
                    migrationManager.startMonitoring(allTasks: allTasks)
                    cleanupOldTasks()
                }
        } else {
            AuthView()
                .onAppear {
                    syncManager.start(context: modelContext)
                }
        }
    }
    
    // MARK: - Main App View
    
    @ViewBuilder
    private var mainAppView: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 40) {
                    HabitsBarView()
                    
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
                                                    .foregroundColor(.secondary)
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
                                                .foregroundColor(.secondary)
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
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation { isCompletedExpanded.toggle() }
                                    }
                            }
                            .tint(.secondary)
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
                                                    .foregroundColor(.secondary)
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
                                                .foregroundColor(.secondary)
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
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation { isDeletedExpanded.toggle() }
                                    }
                            }
                            .tint(.secondary)
                            .onChange(of: isDeletedExpanded) { _, newValue in
                                if !newValue { showAllDeleted = false }
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(40)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedTaskId = nil
            }
            .refreshable {
                await syncManager.triggerManualSync()
            }
            
            // Minimalist Sync Indicator / Trigger in Top Right
            VStack(alignment: .trailing, spacing: 8) {
                HStack {
                    Spacer()
                    Button(action: {
                        Task { await syncManager.triggerManualSync() }
                    }) {
                        HStack(spacing: 6) {
                            if syncManager.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Manual Sync (⌘R)")
                }
                
                if let err = syncManager.lastError {
                    HStack(spacing: 8) {
                        Text(err)
                            .font(.system(size: 10, weight: .light))
                            .foregroundColor(.red)
                            .lineLimit(2)
                        Button(action: { syncManager.lastError = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.08))
                    )
                }
                
                Spacer()
            }
            .padding(.top, 20)
            .padding(.trailing, 24)
            
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
                        SupabaseSyncManager.shared.push()
                        migrationManager.currentMigration = nil
                    },
                    onSkip: {
                        migrationManager.skipMigration(allTasks: allTasks)
                    }
                )
            }
        }
    }
    
    // MARK: - Actions
    
    private func clearCompletedTasks() {
        let completedTasks = allTasks.filter { $0.completed && $0.deletedAt == nil }
        guard !completedTasks.isEmpty else { return }
        let ids = completedTasks.map { $0.id }
        // First soft-delete so any concurrent pull won't re-create them
        let now = Date()
        for task in completedTasks {
            task.deletedAt = now
            task.updatedAt = now
        }
        try? modelContext.save()
        // Push soft-deletes to Supabase, then hard-delete locally and remotely
        SupabaseSyncManager.shared.push()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            for task in completedTasks {
                modelContext.delete(task)
            }
            try? modelContext.save()
            SupabaseSyncManager.shared.deleteRemote(table: "tasks", ids: ids)
        }
    }
    
    private func clearDeletedTasks() {
        let deletedTasks = allTasks.filter { $0.deletedAt != nil }
        guard !deletedTasks.isEmpty else { return }
        let ids = deletedTasks.map { $0.id }
        for task in deletedTasks {
            modelContext.delete(task)
        }
        try? modelContext.save()
        SupabaseSyncManager.shared.deleteRemote(table: "tasks", ids: ids)
    }
    
    private func cleanupOldTasks() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        var idsToDelete: [String] = []
        for task in allTasks {
            if let deletedAt = task.deletedAt, deletedAt < thirtyDaysAgo {
                idsToDelete.append(task.id)
                modelContext.delete(task)
            } else if let completedAt = task.completedAt, completedAt < thirtyDaysAgo {
                idsToDelete.append(task.id)
                modelContext.delete(task)
            }
        }
        if !idsToDelete.isEmpty {
            SupabaseSyncManager.shared.deleteRemote(table: "tasks", ids: idsToDelete)
        }
    }
}
