import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \TaskItem.order) private var allTasks: [TaskItem]
    @Query(sort: \HabitItem.order) private var allHabits: [HabitItem]
    
    @StateObject private var migrationManager = MigrationManager()
    @StateObject private var syncManager = SupabaseSyncManager.shared
    @ObservedObject private var dragState = DragState.shared
    
    @ObservedObject private var locManager = LocalizationManager.shared
    
    @State private var isCompletedExpanded = false
    @State private var isDeletedExpanded = false
    @State private var showAllCompleted = false
    @State private var showAllDeleted = false
    @State private var focusedTaskId: String?
    @State private var currentViewMode: ViewMode = .intervals
    @State private var showSettingsPopover: Bool = false
    
    enum ViewMode {
        case intervals
        case scratchpad
        case settings
    }
    
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
                    migrationManager.startMonitoring(context: modelContext)
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
                    if currentViewMode == .scratchpad {
                        ScratchpadView(focusedTaskId: $focusedTaskId)
                    } else if currentViewMode == .settings {
                        SettingsView(onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentViewMode = .intervals
                            }
                        })
                    } else {
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
                }
                .padding(40)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedTaskId = nil
                #if os(iOS)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }
            .refreshable {
                focusedTaskId = nil
                #if os(iOS)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
                await syncManager.triggerManualSync()
            }
            
            // Minimalist View Switcher & Sync Indicator in Top Right
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    
                    // View Mode Switcher Button
                    Button(action: {
                        focusedTaskId = nil
                        #if os(iOS)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentViewMode = (currentViewMode == .scratchpad ? .intervals : .scratchpad)
                        }
                    }) {
                        ZStack {
                            Image(systemName: currentViewMode == .scratchpad ? "chart.bar" : "doc.plaintext")
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(currentViewMode == .scratchpad ? 0.12 : 0.04))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(currentViewMode == .scratchpad ? "Switch to Interval Tasks".localized : "Switch to Scratchpad Lists".localized)
                    
                    // Settings Button
                    Button(action: {
                        focusedTaskId = nil
                        #if os(iOS)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentViewMode = (currentViewMode == .settings ? .intervals : .settings)
                        }
                    }) {
                        ZStack {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(currentViewMode == .settings ? .primary : .secondary)
                        }
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(currentViewMode == .settings ? 0.12 : 0.04))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Settings".localized)
                    
                    // Refresh / Sync Button
                    Button(action: {
                        focusedTaskId = nil
                        #if os(iOS)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                        Task { await syncManager.triggerManualSync() }
                    }) {
                        ZStack {
                            if syncManager.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Manual Sync (⌘R)".localized)
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
                    habits: HabitTaskLink.selectableHabits(
                        from: allHabits,
                        hourTasks: allTasks.filter { $0.intervalType == HabitTaskLink.hourInterval }
                    ),
                    onMigrate: { selectedTaskIds, selectedHabitIds in
                        migrationManager.executeMigration(
                            migration: migration,
                            selectedTaskIds: selectedTaskIds,
                            selectedHabitIds: selectedHabitIds
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
                        migrationManager.skipMigration()
                    }
                )
            }
        }
    }
    
    // MARK: - Actions
    
    private func clearCompletedTasks() {
        TaskHousekeeping.deletePermanently(TaskHousekeeping.completed(from: allTasks), in: modelContext)
    }
    
    private func clearDeletedTasks() {
        TaskHousekeeping.deletePermanently(TaskHousekeeping.binned(from: allTasks), in: modelContext)
    }
    
    private func cleanupOldTasks() {
        TaskHousekeeping.deletePermanently(TaskHousekeeping.expired(from: allTasks), in: modelContext)
    }
}
