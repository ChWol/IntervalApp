import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine
#if os(macOS)
import AppKit
#endif

// MARK: - Weekday Option Helper

struct WeekdayOption: Identifiable {
    let id: Int // 1 = Sun, 2 = Mon, 3 = Tue, 4 = Wed, 5 = Thu, 6 = Fri, 7 = Sat (Calendar.component(.weekday))
    let shortNameEn: String
    let shortNameDe: String
    let fullNameEn: String
    let fullNameDe: String
    
    var shortName: String {
        LocalizationManager.shared.currentLanguage == .german ? shortNameDe : shortNameEn
    }
    
    var fullName: String {
        LocalizationManager.shared.currentLanguage == .german ? fullNameDe : fullNameEn
    }
    
    static let allMondayFirst: [WeekdayOption] = [
        WeekdayOption(id: 2, shortNameEn: "Mon", shortNameDe: "Mo", fullNameEn: "Monday", fullNameDe: "Montag"),
        WeekdayOption(id: 3, shortNameEn: "Tue", shortNameDe: "Di", fullNameEn: "Tuesday", fullNameDe: "Dienstag"),
        WeekdayOption(id: 4, shortNameEn: "Wed", shortNameDe: "Mi", fullNameEn: "Wednesday", fullNameDe: "Mittwoch"),
        WeekdayOption(id: 5, shortNameEn: "Thu", shortNameDe: "Do", fullNameEn: "Thursday", fullNameDe: "Donnerstag"),
        WeekdayOption(id: 6, shortNameEn: "Fri", shortNameDe: "Fr", fullNameEn: "Friday", fullNameDe: "Freitag"),
        WeekdayOption(id: 7, shortNameEn: "Sat", shortNameDe: "Sa", fullNameEn: "Saturday", fullNameDe: "Samstag"),
        WeekdayOption(id: 1, shortNameEn: "Sun", shortNameDe: "So", fullNameEn: "Sunday", fullNameDe: "Sonntag")
    ]
    
    static func option(for id: Int) -> WeekdayOption? {
        allMondayFirst.first(where: { $0.id == id })
    }
}

// MARK: - Habits Bar View

struct HabitsBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \HabitItem.order) private var habits: [HabitItem]
    @ObservedObject private var locManager = LocalizationManager.shared
    
    @State private var newHabitText: String = ""
    @State private var isAdding: Bool = false
    @State private var selectedFrequency: String = "Daily"
    @State private var selectedWeekday: Int? = nil
    @State private var showWeekdayPopover: Bool = false
    @State private var hoveredHabitId: String? = nil
    @State private var isPlusHovered: Bool = false
    @FocusState private var isInputFocused: Bool
    #if os(macOS)
    @State private var escMonitor: Any? = nil
    #endif
    
    private var sortedHabits: [HabitItem] {
        let active = habits.filter { $0.deletedAt == nil && $0.isScheduledForTodayOrOverdue() }
        let overdueIncomplete = active.filter { $0.isOverdue() && !$0.isCompletedCurrentPeriod }
            .sorted { $0.order < $1.order }
        let todayIncomplete = active.filter { !$0.isOverdue() && !$0.isCompletedCurrentPeriod }
            .sorted { $0.order < $1.order }
        let completed = active.filter { $0.isCompletedCurrentPeriod }.sorted {
            ($0.lastCompletedDate ?? Date.distantPast) > ($1.lastCompletedDate ?? Date.distantPast)
        }
        return overdueIncomplete + todayIncomplete + completed
    }
    
    private var weeklyButtonLabel: String {
        if let day = selectedWeekday, let opt = WeekdayOption.option(for: day) {
            return "weekly (\(opt.shortName))"
        }
        return "weekly"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HABITS".localized)
                .font(.system(size: 10, weight: .light, design: .default))
                .tracking(2.0)
                .foregroundColor(.gray)
            
            // Habits Chips Container
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sortedHabits) { habit in
                            HabitChipView(habit: habit, hoveredHabitId: $hoveredHabitId)
                                .id(habit.id)
                                .onDrag {
                                    HabitDragState.shared.draggedHabit = habit
                                    return NSItemProvider(object: habit.id as NSString)
                                }
                                .onDrop(of: [.data], delegate: HabitDropDelegate(item: habit, context: modelContext, proxy: proxy))
                        }
                    
                    if !isAdding {
                        Button(action: {
                            withAnimation {
                                isAdding = true
                                selectedFrequency = "Daily"
                                selectedWeekday = nil
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                isInputFocused = true
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(isPlusHovered ? .primary : .gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(colorScheme == .dark ? (isPlusHovered ? 0.2 : 0.12) : (isPlusHovered ? 0.12 : 0.06)))
                                )
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .onHover { hovering in
                            isPlusHovered = hovering
                        }
                    } else {
                        HStack(spacing: 8) {
                            // Minimalist Daily | Weekly Toggle
                            HStack(spacing: 6) {
                                Button("daily") {
                                    withAnimation {
                                        selectedFrequency = "Daily"
                                        selectedWeekday = nil
                                        showWeekdayPopover = false
                                    }
                                }
                                .foregroundColor(selectedFrequency == "Daily" ? .primary : .secondary)
                                .font(.system(size: 10, weight: selectedFrequency == "Daily" ? .medium : .light))
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                
                                Text("|")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray.opacity(0.4))
                                
                                Button(action: {
                                    if selectedWeekday == nil {
                                        let currentDay = Calendar.current.component(.weekday, from: Date())
                                        selectedWeekday = currentDay
                                        selectedFrequency = "Weekly:\(currentDay)"
                                    }
                                    showWeekdayPopover = true
                                }) {
                                    Text(weeklyButtonLabel)
                                        .foregroundColor(selectedFrequency.starts(with: "Weekly") ? .primary : .secondary)
                                        .font(.system(size: 10, weight: selectedFrequency.starts(with: "Weekly") ? .medium : .light))
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                .popover(isPresented: $showWeekdayPopover, arrowEdge: .bottom) {
                                    weekdayPickerPopover
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.18 : 0.1))
                            )
                            
                            TextField("Habit name...", text: $newHabitText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .light))
                                .frame(width: 120)
                                .focused($isInputFocused)
                                .onSubmit { createHabit() }
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        isInputFocused = true
                                    }
                                }
                            
                            Button(action: createHabit) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            
                            Button(action: {
                                withAnimation {
                                    isAdding = false
                                    newHabitText = ""
                                    showWeekdayPopover = false
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        #if os(macOS)
                        .onExitCommand {
                            withAnimation {
                                isAdding = false
                                newHabitText = ""
                                showWeekdayPopover = false
                            }
                        }
                        #endif
                    }
                    
                    if habits.isEmpty && !isAdding {
                        Text("No habits added yet. Click + New Habit to set daily or weekly routines.")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        }
        .padding(.bottom, 20)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: colorScheme == .dark ? 0.15 : 0.9)),
            alignment: .bottom
        )
        .onChange(of: showWeekdayPopover) { _, isShowing in
            #if os(macOS)
            if isShowing {
                escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 53 { // ESC
                        showWeekdayPopover = false
                        return nil
                    }
                    return event
                }
            } else {
                if let monitor = escMonitor {
                    NSEvent.removeMonitor(monitor)
                    escMonitor = nil
                }
            }
            #endif
        }
        .onDisappear {
            #if os(macOS)
            if let monitor = escMonitor {
                NSEvent.removeMonitor(monitor)
                escMonitor = nil
            }
            #endif
        }
    }
    
    // MARK: - Weekday Picker Popover Content
    
    @ViewBuilder
    private var weekdayPickerPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SELECT DAY OF WEEK".localized)
                .font(.system(size: 9, weight: .light))
                .tracking(1.5)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            VStack(spacing: 1) {
                ForEach(WeekdayOption.allMondayFirst) { opt in
                    Button(action: {
                        selectedWeekday = opt.id
                        selectedFrequency = "Weekly:\(opt.id)"
                        showWeekdayPopover = false
                    }) {
                        HStack {
                            Text(opt.fullName)
                                .font(.system(size: 12, weight: selectedWeekday == opt.id ? .medium : .light))
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedWeekday == opt.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedWeekday == opt.id ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .frame(minWidth: 150)
        #if os(macOS)
        .onExitCommand { showWeekdayPopover = false }
        #endif
        .background(
            Button("") { showWeekdayPopover = false }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        )
    }
    
    private func createHabit() {
        let trimmed = newHabitText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            withAnimation { isAdding = false }
            return
        }
        newHabitText = ""
        let maxOrder = (habits.map { $0.order }.max() ?? -1) + 1
        let newHabit = HabitItem(text: trimmed, frequency: selectedFrequency, order: maxOrder)
        modelContext.insert(newHabit)
        try? modelContext.save()
        SupabaseSyncManager.shared.push()
        withAnimation {
            isAdding = false
            showWeekdayPopover = false
        }
    }
}

// MARK: - Habit Chip Component

struct HabitChipView: View {
    @Bindable var habit: HabitItem
    @Binding var hoveredHabitId: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var dragState = HabitDragState.shared
    
    private var isDragged: Bool {
        dragState.draggedHabit?.id == habit.id
    }
    
    var body: some View {
        let isDone = habit.isCompletedCurrentPeriod
        let isOverdue = habit.isOverdue() && !isDone
        
        HStack(spacing: 8) {
            Button(action: toggleCompletion) {
                HStack(spacing: 6) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(isDone ? .primary : (isOverdue ? .primary : .secondary))
                    
                    Text(habit.text)
                        .font(.system(size: 12, weight: isOverdue ? .medium : .light))
                        .foregroundColor(isDone ? .secondary : .primary)
                        .strikethrough(isDone)
                    
                    if habit.isWeekly, let day = habit.targetWeekday, let opt = WeekdayOption.option(for: day) {
                        Text(opt.shortName)
                            .font(.system(size: 9, weight: isOverdue ? .medium : .light))
                            .foregroundColor(isOverdue ? .primary : .secondary.opacity(0.8))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.primary.opacity(isOverdue ? (colorScheme == .dark ? 0.22 : 0.12) : 0.06))
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            
            if hoveredHabitId == habit.id {
                Button(action: deleteHabit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDone ? Color.gray.opacity(colorScheme == .dark ? 0.12 : 0.06) : Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.1))
        )
        .opacity(isDragged ? 0.3 : 1.0)
        .onHover { hovering in
            hoveredHabitId = hovering ? habit.id : nil
        }
    }
    
    private func toggleCompletion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            let now = Date()
            let willBeCompleted = !habit.isCompletedCurrentPeriod
            if willBeCompleted {
                SoundManager.playHabitCompleted()
            } else {
                SoundManager.playUndo()
            }
            HabitTaskLink.setHabitCompleted(willBeCompleted, on: habit, now: now)
            // Keep any hour task created from this habit in step with it.
            if let tasks = try? modelContext.fetch(FetchDescriptor<TaskItem>()) {
                HabitTaskLink.applyHabitCompletionToTasks(habit, tasks: tasks, now: now)
            }
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
    
    private func deleteHabit() {
        SoundManager.playTaskDeleted()
        withAnimation {
            let now = Date()
            habit.deletedAt = now
            habit.updatedAt = now
            // Drop any hour tasks that still represent this habit.
            if let tasks = try? modelContext.fetch(FetchDescriptor<TaskItem>()) {
                _ = HabitTaskLink.binLinkedHourTasks(for: habit, tasks: tasks, now: now)
            }
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
}

// MARK: - Habit Drag & Drop Reordering

class HabitDragState: ObservableObject {
    static let shared = HabitDragState()
    @Published var draggedHabit: HabitItem?
}

struct HabitDropDelegate: DropDelegate {
    let item: HabitItem
    let context: ModelContext
    var proxy: ScrollViewProxy? = nil

    func dropEntered(info: DropInfo) {
        guard let draggedItem = HabitDragState.shared.draggedHabit else { return }
        if draggedItem.id != item.id {
            withAnimation(.easeInOut(duration: 0.2)) {
                let descriptor = FetchDescriptor<HabitItem>()
                guard let allHabits = try? context.fetch(descriptor) else { return }
                // Soft-deleted habits stay out of the order so they cannot steal slots.
                var sorted = allHabits.filter { $0.deletedAt == nil }.sorted { $0.order < $1.order }
                
                if let sourceIdx = sorted.firstIndex(where: { $0.id == draggedItem.id }),
                   let targetIdx = sorted.firstIndex(where: { $0.id == item.id }) {
                    let moved = sorted.remove(at: sourceIdx)
                    sorted.insert(moved, at: targetIdx)
                }
                
                let now = Date()
                for (i, h) in sorted.enumerated() {
                    h.order = i
                    h.updatedAt = now
                }
                try? context.save()
                SupabaseSyncManager.shared.push()
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy?.scrollTo(item.id, anchor: .center)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.easeInOut(duration: 0.15)) {
            HabitDragState.shared.draggedHabit = nil
        }
        return true
    }
}
