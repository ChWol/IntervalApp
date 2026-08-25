import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \TaskItem.order) private var allTasks: [TaskItem]
    @Query(sort: \HabitItem.order) private var allHabits: [HabitItem]
    @Query(sort: \ScratchpadList.order) private var allScratchpadLists: [ScratchpadList]
    
    @StateObject private var migrationManager = MigrationManager()
    @StateObject private var syncManager = SupabaseSyncManager.shared
    @ObservedObject private var dragState = DragState.shared
    
    @ObservedObject private var locManager = LocalizationManager.shared
    @AppStorage("showHabits") private var showHabits: Bool = true
    @AppStorage("hasDismissedOnboardingImport") private var hasDismissedOnboardingImport: Bool = false
    
    @State private var isCompletedExpanded = false
    @State private var isDeletedExpanded = false
    @State private var showAllCompleted = false
    @State private var showAllDeleted = false
    @State private var focusedTaskId: String?
    @State private var currentViewMode: ViewMode = .intervals
    @State private var isSearchPresented = false
    @State private var scratchpadSelectedListId: String? = nil
    @State private var showUpdatePasswordModal = false
    @State private var showImportModal = false
    
    @State private var hoveredTopButton: String? = nil
    @State private var isOnboardingImportHovered = false
    @State private var isOnboardingFreshHovered = false
    @State private var isOnboardingCloseHovered = false
    
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
        ZStack {
            Group {
                if syncManager.isAuthenticated {
                    mainAppView
                        .onAppear {
                            syncManager.start(context: modelContext)
                            migrationManager.startMonitoring(context: modelContext)
                            cleanupOldTasks()
                        }
                        .onChange(of: syncManager.isAuthenticated) { _, authenticated in
                            if authenticated {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentViewMode = .intervals
                                    focusedTaskId = nil
                                }
                            }
                        }
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active {
                                Task {
                                    await syncManager.triggerManualSync()
                                    migrationManager.checkMigrations()
                                }
                            }
                        }
                } else {
                    AuthView()
                        .onAppear {
                            syncManager.start(context: modelContext)
                            currentViewMode = .intervals
                        }
                }
            }
            .environment(\.layoutDirection, locManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight)
            
            if showUpdatePasswordModal {
                UpdatePasswordModalView(isPresented: $showUpdatePasswordModal)
                    .zIndex(200)
            }
        }
        .onOpenURL { url in
            syncManager.handleIncomingURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .promptPasswordUpdate)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showUpdatePasswordModal = true
            }
        }
    }
    
    // MARK: - Main App View
    
    @ViewBuilder
    private var mainAppView: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            if currentViewMode == .settings {
                SettingsView(onClose: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentViewMode = .intervals
                    }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                GeometryReader { geo in
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 40) {
                                if currentViewMode == .scratchpad {
                                    ScratchpadView(focusedTaskId: $focusedTaskId, selectedListId: $scratchpadSelectedListId)
                                } else {
                                    if isAccountEmpty && !hasDismissedOnboardingImport {
                                        onboardingImportCard
                                    }
                                    
                                    if showHabits {
                                        HabitsBarView()
                                    }
                                    
                                    ForEach(intervals, id: \.0) { interval in
                                        TaskListView(
                                            title: interval.0,
                                            fontSize: interval.1,
                                            tasks: allTasks.filter { $0.intervalType == interval.0 && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order },
                                            focusedTaskId: $focusedTaskId
                                        )
                                    }
                                
                                    completedAndDeletedSection
                                }
                            }
                            .padding(40)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            focusedTaskId = nil
                            NotificationCenter.default.post(name: .scratchpadClearSelection, object: nil)
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
                        .onChange(of: focusedTaskId) { _, newId in
                            if let id = newId {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    scrollProxy.scrollTo(id, anchor: nil)
                                }
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .taskTextDidGrow)) { _ in
                            if let id = focusedTaskId {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    scrollProxy.scrollTo(id, anchor: nil)
                                }
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .focusNextTask)) { notification in
                            guard let currentId = notification.userInfo?["currentId"] as? String,
                                  let direction = notification.userInfo?["direction"] as? String else { return }
                            handleFocusNavigation(from: currentId, direction: direction)
                        }
                    }
                }
            }
            
            // Minimalist View Switcher & Sync Indicator in Top Right
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    
                    // Main Page Button
                    Button(action: {
                        focusedTaskId = nil
                        #if os(iOS)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentViewMode = .intervals
                        }
                    }) {
                        let isHovered = hoveredTopButton == "intervals"
                        ZStack {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(currentViewMode == .intervals ? .primary : (isHovered ? .primary : .secondary))
                        }
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(currentViewMode == .intervals ? 0.12 : (isHovered ? 0.08 : 0.04)))
                        )
                        .scaleEffect(isHovered ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hoveredTopButton = h ? "intervals" : nil } }
                    .help("Switch to Interval Tasks".localized)
                    
                    // Scratchpad Lists Button
                    Button(action: {
                        focusedTaskId = nil
                        #if os(iOS)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentViewMode = .scratchpad
                        }
                    }) {
                        let isHovered = hoveredTopButton == "scratchpad"
                        ZStack {
                            Image(systemName: "doc.plaintext")
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(currentViewMode == .scratchpad ? .primary : (isHovered ? .primary : .secondary))
                        }
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(currentViewMode == .scratchpad ? 0.12 : (isHovered ? 0.08 : 0.04)))
                        )
                        .scaleEffect(isHovered ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hoveredTopButton = h ? "scratchpad" : nil } }
                    .help("Switch to Scratchpad Lists".localized)
                    
                    // Settings Button
                    Button(action: {
                        focusedTaskId = nil
                        #if os(iOS)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentViewMode = .settings
                        }
                    }) {
                        let isHovered = hoveredTopButton == "settings"
                        ZStack {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(currentViewMode == .settings ? .primary : (isHovered ? .primary : .secondary))
                        }
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(currentViewMode == .settings ? 0.12 : (isHovered ? 0.08 : 0.04)))
                        )
                        .scaleEffect(isHovered ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hoveredTopButton = h ? "settings" : nil } }
                    .help("Settings".localized)
                    
                    // Search Button
                    Button(action: {
                        focusedTaskId = nil
                        #if os(iOS)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isSearchPresented.toggle()
                        }
                    }) {
                        let isHovered = hoveredTopButton == "search"
                        ZStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(isSearchPresented ? .primary : (isHovered ? .primary : .secondary))
                        }
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(isSearchPresented ? 0.12 : (isHovered ? 0.08 : 0.04)))
                        )
                        .scaleEffect(isHovered ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hoveredTopButton = h ? "search" : nil } }
                    .help("Search (⌘F)".localized)
                    
                    // Refresh / Sync Button
                    Button(action: {
                        focusedTaskId = nil
                        #if os(iOS)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                        Task { await syncManager.triggerManualSync() }
                    }) {
                        let isHovered = hoveredTopButton == "sync"
                        ZStack {
                            if syncManager.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(isHovered ? .primary : .secondary)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(isHovered ? 0.08 : 0.04))
                        )
                        .scaleEffect(isHovered ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hoveredTopButton = h ? "sync" : nil } }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Manual Sync (⌘R)".localized)
                }
                
                // Hidden shortcut triggers for search (⌘F and ⌘K)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isSearchPresented.toggle()
                    }
                }) {
                    EmptyView()
                }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isSearchPresented.toggle()
                    }
                }) {
                    EmptyView()
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                
                #if os(macOS)
                Button(action: {
                    PrintManager.printIntervals(context: modelContext)
                }) {
                    EmptyView()
                }
                .buttonStyle(.plain)
                .keyboardShortcut("p", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                #endif
                
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
            

            
            if isSearchPresented {
                SpotlightSearchView(
                    isPresented: $isSearchPresented,
                    onSelect: { item in
                        handleSearchSelection(item)
                    }
                )
                .zIndex(100)
            }
            
            if showImportModal {
                MigrationImportModalView(isPresented: $showImportModal)
                    .zIndex(150)
            }
            
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
    
    // MARK: - Completed & Deleted Lists Section
    
    @ViewBuilder
    private var completedAndDeletedSection: some View {
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
                                Button(action: {
                                    withAnimation { showAllCompleted.toggle() }
                                }) {
                                    Text(showAllCompleted ? "Show Less".localized : "\("Show All".localized) (\(completedTasks.count))")
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation {
                                    clearCompletedTasks()
                                }
                            }) {
                                Text("Clear All".localized)
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.leading, 12)
                    .padding(.top, 8)
                } label: {
                    Text("\("COMPLETED".localized) (\(completedTasks.count))")
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
                                Button(action: {
                                    withAnimation { showAllDeleted.toggle() }
                                }) {
                                    Text(showAllDeleted ? "Show Less".localized : "\("Show All".localized) (\(deletedTasks.count))")
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation {
                                    clearDeletedTasks()
                                }
                            }) {
                                Text("Empty Bin".localized)
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.leading, 12)
                    .padding(.top, 8)
                } label: {
                    Text("\("BIN".localized) (\(deletedTasks.count))")
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
    
    // MARK: - Onboarding Import Card
    
    private var isAccountEmpty: Bool {
        allTasks.filter { $0.deletedAt == nil }.isEmpty &&
        allHabits.filter { $0.deletedAt == nil }.isEmpty &&
        allScratchpadLists.filter { $0.deletedAt == nil }.isEmpty
    }
    
    @ViewBuilder
    private var onboardingImportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WELCOME TO INTERVAL".localized)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.0)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hasDismissedOnboardingImport = true
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(isOnboardingCloseHovered ? 0.1 : 0.0))
                            .frame(width: 22, height: 22)
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .light))
                            .foregroundColor(isOnboardingCloseHovered ? .primary : .secondary.opacity(0.7))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isOnboardingCloseHovered = h
                    }
                }
            }
            
            Text("Import your existing tasks from TickTick, Microsoft To Do, Todoist or Apple Reminders, or start fresh.".localized)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 16) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showImportModal = true
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                        Text("Import Tasks".localized)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(isOnboardingImportHovered ? 0.88 : 1.0))
                    )
                    .scaleEffect(isOnboardingImportHovered ? 1.03 : 1.0)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isOnboardingImportHovered = h
                    }
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hasDismissedOnboardingImport = true
                    }
                }) {
                    Text("Start Fresh".localized)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(isOnboardingFreshHovered ? .primary : .secondary)
                        .underline(isOnboardingFreshHovered)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isOnboardingFreshHovered = h
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
    
    // MARK: - Actions
    
    private func handleSearchSelection(_ item: SearchResultItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch item.destination {
            case .interval:
                currentViewMode = .intervals
                focusedTaskId = item.targetId
            case .habit:
                currentViewMode = .intervals
                focusedTaskId = nil
            case .scratchpad(let listId):
                scratchpadSelectedListId = listId
                currentViewMode = .scratchpad
                focusedTaskId = item.targetId
            }
        }
    }
    
    private func clearCompletedTasks() {
        TaskHousekeeping.deletePermanently(TaskHousekeeping.completed(from: allTasks), in: modelContext)
    }
    
    private func clearDeletedTasks() {
        TaskHousekeeping.deletePermanently(TaskHousekeeping.binned(from: allTasks), in: modelContext)
    }
    
    private func cleanupOldTasks() {
        TaskHousekeeping.deletePermanently(TaskHousekeeping.expired(from: allTasks), in: modelContext)
    }
    
    private func handleFocusNavigation(from currentId: String, direction: String) {
        if currentViewMode == .scratchpad {
            let descriptor = FetchDescriptor<ScratchpadItem>()
            if let allItems = try? modelContext.fetch(descriptor) {
                let listItems = allItems.filter { $0.deletedAt == nil && !$0.completed && $0.listId == scratchpadSelectedListId }.sorted { $0.order < $1.order }
                if let currentIndex = listItems.firstIndex(where: { $0.id == currentId }) {
                    let targetIndex = direction == "forward" ? currentIndex + 1 : currentIndex - 1
                    if targetIndex >= 0 && targetIndex < listItems.count {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            focusedTaskId = listItems[targetIndex].id
                        }
                    }
                }
            }
        } else {
            let intervalOrder = ["1 Hour", "1 Day", "1 Week", "1 Month", "1 Year"]
            var allOrderedTasks: [TaskItem] = []
            for interval in intervalOrder {
                let sectionTasks = allTasks.filter { $0.intervalType == interval && $0.deletedAt == nil && !$0.completed }
                    .sorted { $0.order < $1.order }
                allOrderedTasks.append(contentsOf: sectionTasks)
            }
            
            if let currentIndex = allOrderedTasks.firstIndex(where: { $0.id == currentId }) {
                let targetIndex = direction == "forward" ? currentIndex + 1 : currentIndex - 1
                if targetIndex >= 0 && targetIndex < allOrderedTasks.count {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        focusedTaskId = allOrderedTasks[targetIndex].id
                    }
                }
            }
        }
    }
}
