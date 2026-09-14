#if !os(watchOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TaskListView: View {
    let title: String
    let fontSize: CGFloat
    let tasks: [TaskItem]
    @Binding var focusedTaskId: String?
    var onDeepFocus: ((TaskItem) -> Void)? = nil
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var habitDragState = HabitDragState.shared
    @ObservedObject private var taskDragState = DragState.shared

    @State private var isPlusHovered: Bool = false

    private var isHourSection: Bool {
        title == HabitTaskLink.hourInterval
    }

    private var habitAlreadyInHour: Bool {
        guard let dragged = habitDragState.draggedHabit else { return false }
        return tasks.contains { $0.habitId == dragged.id && $0.deletedAt == nil && !$0.completed }
    }

    private var shouldShowHabitPlaceholder: Bool {
        isHourSection && habitDragState.draggedHabit != nil && habitDragState.isTargetingHour && !habitAlreadyInHour
    }

    private var shouldShowTaskPlaceholder: Bool {
        taskDragState.draggedTask != nil && taskDragState.targetIntervalType == title && taskDragState.targetIndex != nil
    }

    private func insertionIndex(before row: Int) -> Int {
        let sourceId = taskDragState.draggedTask?.id
        return tasks.prefix(row).filter { $0.id != sourceId }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: max(5, fontSize * 0.4)) {
            // Category Header with subtle + button: Drop here to place at top of list
            HStack {
                Text(title.uppercased().localized)
                    .font(.system(size: 10, weight: .light, design: .default))
                    .tracking(2.0)
                    .foregroundColor(.gray)
                    .onboardingTarget(title)
                
                Spacer()
                
                Button(action: {
                    createNewTaskAtEnd()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(isPlusHovered ? .primary : .secondary.opacity(0.4))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isPlusHovered = hovering
                    }
                }
                .onboardingTarget(title == "1 Hour" ? "hourAdd" : "taskAdd-\(title)")
            }
            #if !os(watchOS)
            .padding(.bottom, 5)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.data, UTType.plainText, UTType.text], delegate: TaskListHeaderDropDelegate(listTitle: title, sectionFontSize: fontSize, context: modelContext))
            #else
            .padding(.bottom, 5)
            #endif
            .id("onboarding-\(title)")
            
            // Keep the source view mounted: removing it cancels the native
            // iPhone drag provider before SwiftUI calls performDrop.
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                if shouldShowTaskPlaceholder && taskDragState.targetIndex == insertionIndex(before: index)
                    && (index == 0 || insertionIndex(before: index) != insertionIndex(before: index - 1)) {
                    taskInsertionPlaceholder
                        .onDrop(of: [UTType.data, UTType.plainText, UTType.text],
                                delegate: TaskListInsertionDropDelegate(listTitle: title, index: insertionIndex(before: index), context: modelContext))
                }
                if shouldShowHabitPlaceholder && habitDragState.targetIndex == index {
                    habitInsertionPlaceholder
                        .onDrop(of: [UTType.data, UTType.plainText, UTType.text],
                                delegate: TaskListInsertionDropDelegate(listTitle: title, index: index, context: modelContext))
                }
                
                TaskRowView(task: task, fontSize: fontSize, isNew: false, listTitle: title, onDeepFocus: onDeepFocus, focusedTaskId: $focusedTaskId, showsOnboardingTargets: title == "1 Hour" && index == 0)
            }

            if shouldShowTaskPlaceholder && taskDragState.targetIndex == insertionIndex(before: tasks.count) {
                taskInsertionPlaceholder
                    .onDrop(of: [UTType.data, UTType.plainText, UTType.text],
                            delegate: TaskListInsertionDropDelegate(listTitle: title, index: insertionIndex(before: tasks.count), context: modelContext))
            }
            
            if shouldShowHabitPlaceholder && (habitDragState.targetIndex == tasks.count || (tasks.isEmpty && habitDragState.isTargetingHour)) {
                habitInsertionPlaceholder
                    .onDrop(of: [UTType.data, UTType.plainText, UTType.text],
                            delegate: TaskListInsertionDropDelegate(listTitle: title, index: tasks.count, context: modelContext))
            }
            
            if tasks.isEmpty && !shouldShowHabitPlaceholder {
                TaskRowView(task: TaskItem(text: "", intervalType: title), fontSize: fontSize, isNew: true, listTitle: title, focusedTaskId: $focusedTaskId)
            }
            
            #if !os(watchOS)
            // Bottom Drop Zone: Drop here to place at bottom of list
            Color.clear
                .frame(height: 25)
                .contentShape(Rectangle())
                .onDrop(of: [UTType.data, UTType.plainText, UTType.text], delegate: TaskListBottomDropDelegate(listTitle: title, sectionFontSize: fontSize, context: modelContext))
            #endif
        }
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: colorScheme == .dark ? 0.15 : 0.9)),
            alignment: .bottom
        )
    }
    
    private var habitInsertionPlaceholder: some View {
        HStack(alignment: .center, spacing: max(8, fontSize * 0.5)) {
            Image(systemName: "circle")
                .font(.system(size: max(fontSize * 0.65, 12), weight: .light))
                .foregroundColor(.secondary.opacity(0.35))
            if let habit = habitDragState.draggedHabit {
                Text(habit.text)
                    .font(.system(size: fontSize, weight: .light))
                    .foregroundColor(.secondary.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, max(fontSize * 0.25, 4))
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(colorScheme == .dark ? 0.18 : 0.09)))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .accessibilityLabel("Insert habit here")
    }

    private var taskInsertionPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.08))
            .frame(height: max(fontSize * 1.2, 24))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .accessibilityLabel("Move task here")
    }
    
    private func createNewTaskAtEnd() {
        let descriptor = FetchDescriptor<TaskItem>()
        if let all = try? modelContext.fetch(descriptor) {
            let sorted = all.filter { $0.intervalType == title && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
            let maxOrder = (sorted.last?.order ?? -1) + 1
            let newTask = TaskItem(text: "", intervalType: title, order: maxOrder)
            modelContext.insert(newTask)
            _ = PersistenceSafety.save(modelContext)
            SupabaseSyncManager.shared.push()
            DispatchQueue.main.async {
                focusedTaskId = newTask.id
            }
        }
    }
}

// MARK: - Habit Drop into 1-Hour Helper

/// Creates a new TaskItem linked to the dragged habit and inserts it at the given position
/// in the 1 Hour list. Only works when listTitle == "1 Hour" and habit is not already in 1 Hour.
@MainActor
private final class ActiveHabitInsertion {
    weak var context: ModelContext?
    weak var task: TaskItem?

    init(context: ModelContext, task: TaskItem) {
        self.context = context
        self.task = task
    }
}

@MainActor
private enum HabitInsertionRegistry {
    static var entries: [String: ActiveHabitInsertion] = [:]

    static func hasActiveTask(for habitID: String, in context: ModelContext) -> Bool {
        guard let entry = entries[habitID], entry.context === context,
              let task = entry.task, !task.isDeleted,
              task.deletedAt == nil, !task.completed,
              task.intervalType == HabitTaskLink.hourInterval else {
            entries[habitID] = nil
            return false
        }
        return true
    }

    static func remember(_ task: TaskItem, for habitID: String, in context: ModelContext) {
        entries[habitID] = ActiveHabitInsertion(context: context, task: task)
    }
}

@MainActor
@discardableResult
func insertHabitAsTask(habit: HabitItem, at position: HabitInsertPosition, listTitle: String, context: ModelContext) -> Bool {
    guard listTitle == HabitTaskLink.hourInterval,
          !HabitInsertionRegistry.hasActiveTask(for: habit.id, in: context) else { return false }
    
    let descriptor = FetchDescriptor<TaskItem>()
    guard let allTasks = try? context.fetch(descriptor) else { return false }
    
    // If the habit is already present in 1 Hour as an active task, do NOT insert or duplicate
    let alreadyExists = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
    guard !alreadyExists else { return false }
    
    var sorted = allTasks.filter { $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
    let now = Date()
    
    let newTask = TaskItem(text: habit.text, intervalType: HabitTaskLink.hourInterval, order: 0, habitId: habit.id)
    newTask.updatedAt = now
    context.insert(newTask)
    HabitInsertionRegistry.remember(newTask, for: habit.id, in: context)
    
    switch position {
    case .top:
        sorted.insert(newTask, at: 0)
    case .bottom:
        sorted.append(newTask)
    case .atIndex(let idx):
        let clamped = min(max(0, idx), sorted.count)
        sorted.insert(newTask, at: clamped)
    }
    
    for (i, t) in sorted.enumerated() where t.order != i {
        t.order = i
        t.updatedAt = now
        t.syncedAt = nil
    }
    
    _ = PersistenceSafety.save(context)
    SupabaseSyncManager.shared.push()
    return true
}

@MainActor
@discardableResult
func commitHabitDrop(_ habit: HabitItem, at index: Int, listTitle: String, context: ModelContext) -> Bool {
    guard listTitle == HabitTaskLink.hourInterval,
          HabitDragState.shared.claimDrop(for: habit) else { return false }
    let inserted = insertHabitAsTask(habit: habit, at: .atIndex(index), listTitle: listTitle, context: context)
    withAnimation(.easeInOut(duration: 0.15)) { HabitDragState.shared.reset() }
    return inserted
}

enum HabitInsertPosition {
    case top
    case bottom
    case atIndex(Int)
}

@MainActor
enum TaskDragMutation {
    /// Applies a proposed move only after a real drop. Hover and cancellation do
    /// not touch SwiftData, preventing accidental autosaved moves.
    @discardableResult
    static func commit(_ dragged: TaskItem,
                       to interval: String,
                       index: Int,
                       context: ModelContext,
                       now: Date = Date()) -> Bool {
        guard DataIntegrityRepair.validIntervals.contains(interval) else { return false }
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let sourceInterval = dragged.intervalType
        let intervalChanged = sourceInterval != interval
        var destination = all.filter {
            $0.intervalType == interval && $0.deletedAt == nil && !$0.completed && $0.id != dragged.id
        }.sorted { $0.order < $1.order }
        destination.insert(dragged, at: min(max(index, 0), destination.count))
        dragged.intervalType = interval

        var affected = destination
        if sourceInterval != interval {
            affected += all.filter {
                $0.intervalType == sourceInterval && $0.deletedAt == nil && !$0.completed && $0.id != dragged.id
            }.sorted { $0.order < $1.order }
        }

        var changed = false
        for groupInterval in Set(affected.map(\.intervalType)) {
            let rows = affected.filter { $0.intervalType == groupInterval }
            for (position, task) in rows.enumerated()
            where task.order != position || (task.id == dragged.id && intervalChanged) {
                task.order = position
                task.updatedAt = now
                task.syncedAt = nil
                changed = true
            }
        }
        return changed
    }
}

#if !os(watchOS)
// MARK: - List Drop Delegates

/// The full-height insertion card is itself a drop target. Without this,
/// SwiftUI can end the drag over the visible card instead of the row below it,
/// leaving performDrop uncalled even though the UI advertised a valid slot.
struct TaskListInsertionDropDelegate: DropDelegate {
    let listTitle: String
    let index: Int
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        DragState.shared.noteDragActivity()
        HabitDragState.shared.noteDragActivity()
        if HabitDragState.shared.draggedHabit != nil, listTitle == HabitTaskLink.hourInterval {
            HabitDragState.shared.targetHour(at: index)
        } else if DragState.shared.draggedTask != nil {
            DragState.shared.targetIntervalType = listTitle
            DragState.shared.targetIndex = index
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DragState.shared.noteDragActivity()
        HabitDragState.shared.noteDragActivity()
        if let habit = HabitDragState.shared.draggedHabit {
            guard listTitle == HabitTaskLink.hourInterval else { return DropProposal(operation: .forbidden) }
            let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
            let alreadyPresent = tasks.contains {
                $0.habitId == habit.id && $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed
            }
            return DropProposal(operation: alreadyPresent ? .forbidden : .move)
        }
        return DragState.shared.draggedTask == nil ? DropProposal(operation: .forbidden) : DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        DragState.shared.clearTargetAfterExit()
        HabitDragState.shared.clearTargetAfterExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        Self.commitDrop(to: listTitle, at: index, context: context)
    }

    @MainActor
    static func commitDrop(to listTitle: String, at index: Int, context: ModelContext) -> Bool {
        if let habit = HabitDragState.shared.draggedHabit {
            guard listTitle == HabitTaskLink.hourInterval else { return false }
            return commitHabitDrop(habit, at: index, listTitle: listTitle, context: context)
        }
        guard let task = DragState.shared.draggedTask else { return false }
        let changed = TaskDragMutation.commit(task, to: listTitle, index: index, context: context)
        if changed {
            SoundManager.playTaskDropped()
            _ = PersistenceSafety.save(context)
            SupabaseSyncManager.shared.push()
        }
        withAnimation(.easeInOut(duration: 0.15)) { DragState.shared.reset() }
        return true
    }
}

struct TaskListHeaderDropDelegate: DropDelegate {
    let listTitle: String
    let sectionFontSize: CGFloat
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        DragState.shared.noteDragActivity()
        HabitDragState.shared.noteDragActivity()
        // Handle habit drag entering header
        if let habit = HabitDragState.shared.draggedHabit {
            if listTitle == HabitTaskLink.hourInterval {
                let descriptor = FetchDescriptor<TaskItem>()
                let allTasks = (try? context.fetch(descriptor)) ?? []
                let alreadyInHour = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
                if !alreadyInHour {
                    HabitDragState.shared.targetHour(at: 0)
                }
            }
            return
        }
        
        // Handle regular task drag
        if DragState.shared.draggedTask != nil {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                DragState.shared.targetIntervalType = listTitle
                DragState.shared.targetFontSize = sectionFontSize
                DragState.shared.targetIndex = 0
            }
        }
    }
    
    func dropExited(info: DropInfo) {
        DragState.shared.clearTargetAfterExit()
        HabitDragState.shared.clearTargetAfterExit()
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DragState.shared.noteDragActivity()
        HabitDragState.shared.noteDragActivity()
        if let habit = HabitDragState.shared.draggedHabit {
            if listTitle != HabitTaskLink.hourInterval {
                return DropProposal(operation: .forbidden)
            }
            let descriptor = FetchDescriptor<TaskItem>()
            let allTasks = (try? context.fetch(descriptor)) ?? []
            let alreadyInHour = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
            if alreadyInHour {
                return DropProposal(operation: .forbidden)
            }
            return DropProposal(operation: .move)
        }
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Handle habit drop onto header
        if let habit = HabitDragState.shared.draggedHabit {
            guard listTitle == HabitTaskLink.hourInterval else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    HabitDragState.shared.reset()
                }
                return false
            }
            return commitHabitDrop(habit, at: 0, listTitle: listTitle, context: context)
        }
        
        // Handle regular task drop
        SoundManager.playTaskDropped()
        if let draggedItem = DragState.shared.draggedTask {
            _ = TaskDragMutation.commit(draggedItem, to: listTitle, index: 0, context: context)
        }
        _ = PersistenceSafety.save(context)
        SupabaseSyncManager.shared.push()
        withAnimation(.easeInOut(duration: 0.15)) {
            DragState.shared.reset()
        }
        return true
    }
}

struct TaskListBottomDropDelegate: DropDelegate {
    let listTitle: String
    let sectionFontSize: CGFloat
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        DragState.shared.noteDragActivity()
        HabitDragState.shared.noteDragActivity()
        // Handle habit drag entering bottom zone
        if let habit = HabitDragState.shared.draggedHabit {
            if listTitle == HabitTaskLink.hourInterval {
                let descriptor = FetchDescriptor<TaskItem>()
                let allTasks = (try? context.fetch(descriptor)) ?? []
                let alreadyInHour = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
                if !alreadyInHour {
                    let activeCount = allTasks.filter { $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }.count
                    HabitDragState.shared.targetHour(at: activeCount)
                }
            }
            return
        }
        
        // Handle regular task drag
        if let draggedItem = DragState.shared.draggedTask {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                DragState.shared.targetIntervalType = listTitle
                DragState.shared.targetFontSize = sectionFontSize
                let descriptor = FetchDescriptor<TaskItem>()
                let allTasks = (try? context.fetch(descriptor)) ?? []
                DragState.shared.targetIndex = allTasks.filter {
                    $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed && $0.id != draggedItem.id
                }.count
            }
        }
    }
    
    func dropExited(info: DropInfo) {
        DragState.shared.clearTargetAfterExit()
        HabitDragState.shared.clearTargetAfterExit()
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DragState.shared.noteDragActivity()
        HabitDragState.shared.noteDragActivity()
        if let habit = HabitDragState.shared.draggedHabit {
            if listTitle != HabitTaskLink.hourInterval {
                return DropProposal(operation: .forbidden)
            }
            let descriptor = FetchDescriptor<TaskItem>()
            let allTasks = (try? context.fetch(descriptor)) ?? []
            let alreadyInHour = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
            if alreadyInHour {
                return DropProposal(operation: .forbidden)
            }
            return DropProposal(operation: .move)
        }
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Handle habit drop onto bottom
        if let habit = HabitDragState.shared.draggedHabit {
            guard listTitle == HabitTaskLink.hourInterval else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    HabitDragState.shared.reset()
                }
                return false
            }
            let descriptor = FetchDescriptor<TaskItem>()
            let allTasks = (try? context.fetch(descriptor)) ?? []
            let activeCount = allTasks.filter { $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }.count
            return commitHabitDrop(habit, at: activeCount, listTitle: listTitle, context: context)
        }
        
        // Handle regular task drop
        SoundManager.playTaskDropped()
        if let draggedItem = DragState.shared.draggedTask {
            let count = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter {
                $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed && $0.id != draggedItem.id
            }.count
            _ = TaskDragMutation.commit(draggedItem, to: listTitle, index: count, context: context)
        }
        _ = PersistenceSafety.save(context)
        SupabaseSyncManager.shared.push()
        withAnimation(.easeInOut(duration: 0.15)) {
            DragState.shared.reset()
        }
        return true
    }
}
#endif

#endif
