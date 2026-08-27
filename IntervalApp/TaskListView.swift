import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TaskListView: View {
    let title: String
    let fontSize: CGFloat
    let tasks: [TaskItem]
    @Binding var focusedTaskId: String?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var habitDragState = HabitDragState.shared

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

    var body: some View {
        VStack(alignment: .leading, spacing: max(5, fontSize * 0.4)) {
            // Category Header with subtle + button: Drop here to place at top of list
            HStack {
                Text(title.uppercased().localized)
                    .font(.system(size: 10, weight: .light, design: .default))
                    .tracking(2.0)
                    .foregroundColor(.gray)
                
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
            }
            .padding(.bottom, 5)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.data, UTType.plainText, UTType.text], delegate: TaskListHeaderDropDelegate(listTitle: title, sectionFontSize: fontSize, context: modelContext))
            
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                if shouldShowHabitPlaceholder && habitDragState.targetIndex == index {
                    habitInsertionPlaceholder
                }
                
                TaskRowView(task: task, fontSize: fontSize, isNew: false, listTitle: title, focusedTaskId: $focusedTaskId)
            }
            
            if shouldShowHabitPlaceholder && (habitDragState.targetIndex == tasks.count || (tasks.isEmpty && habitDragState.isTargetingHour)) {
                habitInsertionPlaceholder
            }
            
            if tasks.isEmpty && !shouldShowHabitPlaceholder {
                TaskRowView(task: TaskItem(text: "", intervalType: title), fontSize: fontSize, isNew: true, listTitle: title, focusedTaskId: $focusedTaskId)
            }
            
            // Bottom Drop Zone: Drop here to place at bottom of list
            Color.clear
                .frame(height: 25)
                .contentShape(Rectangle())
                .onDrop(of: [UTType.data, UTType.plainText, UTType.text], delegate: TaskListBottomDropDelegate(listTitle: title, sectionFontSize: fontSize, context: modelContext))
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
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(colorScheme == .dark ? 0.18 : 0.09))
        )
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity
        ))
    }
    
    private func createNewTaskAtEnd() {
        let descriptor = FetchDescriptor<TaskItem>()
        if let all = try? modelContext.fetch(descriptor) {
            let sorted = all.filter { $0.intervalType == title && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
            let maxOrder = (sorted.last?.order ?? -1) + 1
            let newTask = TaskItem(text: "", intervalType: title, order: maxOrder)
            modelContext.insert(newTask)
            try? modelContext.save()
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
func insertHabitAsTask(habit: HabitItem, at position: HabitInsertPosition, listTitle: String, context: ModelContext) {
    guard listTitle == HabitTaskLink.hourInterval else { return }
    
    let descriptor = FetchDescriptor<TaskItem>()
    guard let allTasks = try? context.fetch(descriptor) else { return }
    
    // If the habit is already present in 1 Hour as an active task, do NOT insert or duplicate
    let alreadyExists = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
    guard !alreadyExists else { return }
    
    var sorted = allTasks.filter { $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
    let now = Date()
    
    let newTask = TaskItem(text: habit.text, intervalType: HabitTaskLink.hourInterval, order: 0, habitId: habit.id)
    newTask.updatedAt = now
    context.insert(newTask)
    
    switch position {
    case .top:
        sorted.insert(newTask, at: 0)
    case .bottom:
        sorted.append(newTask)
    case .atIndex(let idx):
        let clamped = min(max(0, idx), sorted.count)
        sorted.insert(newTask, at: clamped)
    }
    
    for (i, t) in sorted.enumerated() {
        t.order = i
    }
    
    try? context.save()
    SupabaseSyncManager.shared.push()
}

enum HabitInsertPosition {
    case top
    case bottom
    case atIndex(Int)
}

// MARK: - List Drop Delegates

struct TaskListHeaderDropDelegate: DropDelegate {
    let listTitle: String
    let sectionFontSize: CGFloat
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        // Handle habit drag entering header
        if let habit = HabitDragState.shared.draggedHabit {
            if listTitle == HabitTaskLink.hourInterval {
                let descriptor = FetchDescriptor<TaskItem>()
                let allTasks = (try? context.fetch(descriptor)) ?? []
                let alreadyInHour = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
                if !alreadyInHour {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        HabitDragState.shared.targetIndex = 0
                        HabitDragState.shared.isTargetingHour = true
                    }
                }
            }
            return
        }
        
        // Handle regular task drag
        if let draggedItem = DragState.shared.draggedTask {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                DragState.shared.targetIntervalType = listTitle
                DragState.shared.targetFontSize = sectionFontSize
                
                draggedItem.intervalType = listTitle
                
                let descriptor = FetchDescriptor<TaskItem>()
                guard let allTasks = try? context.fetch(descriptor) else { return }
                var sorted = allTasks.filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed && $0.id != draggedItem.id }.sorted { $0.order < $1.order }
                
                sorted.insert(draggedItem, at: 0)
                
                for (i, t) in sorted.enumerated() {
                    t.order = i
                }
            }
        }
    }
    
    func dropExited(info: DropInfo) {
        if HabitDragState.shared.draggedHabit != nil {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                HabitDragState.shared.targetIndex = nil
                HabitDragState.shared.isTargetingHour = false
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
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
        if let habit = HabitDragState.shared.draggedHabit {
            guard listTitle == HabitTaskLink.hourInterval else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    HabitDragState.shared.reset()
                }
                return false
            }
            let descriptor = FetchDescriptor<TaskItem>()
            let allTasks = (try? context.fetch(descriptor)) ?? []
            let alreadyInHour = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
            guard !alreadyInHour else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    HabitDragState.shared.reset()
                }
                return false
            }
            
            let targetIdx = HabitDragState.shared.targetIndex ?? 0
            insertHabitAsTask(habit: habit, at: .atIndex(targetIdx), listTitle: listTitle, context: context)
            withAnimation(.easeInOut(duration: 0.15)) {
                HabitDragState.shared.reset()
            }
            return true
        }
        
        // Handle regular task drop
        if let draggedItem = DragState.shared.draggedTask {
            draggedItem.updatedAt = Date()
        }
        try? context.save()
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
        if let habit = HabitDragState.shared.draggedHabit {
            if listTitle == HabitTaskLink.hourInterval {
                let descriptor = FetchDescriptor<TaskItem>()
                let allTasks = (try? context.fetch(descriptor)) ?? []
                let alreadyInHour = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
                if !alreadyInHour {
                    let sorted = allTasks.filter { $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        HabitDragState.shared.targetIndex = sorted.count
                        HabitDragState.shared.isTargetingHour = true
                    }
                }
            }
            return
        }
        
        // Handle regular task drag
        if let draggedItem = DragState.shared.draggedTask {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                DragState.shared.targetIntervalType = listTitle
                DragState.shared.targetFontSize = sectionFontSize
                
                draggedItem.intervalType = listTitle
                
                let descriptor = FetchDescriptor<TaskItem>()
                guard let allTasks = try? context.fetch(descriptor) else { return }
                var sorted = allTasks.filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed && $0.id != draggedItem.id }.sorted { $0.order < $1.order }
                
                sorted.append(draggedItem)
                
                for (i, t) in sorted.enumerated() {
                    t.order = i
                }
            }
        }
    }
    
    func dropExited(info: DropInfo) {
        if HabitDragState.shared.draggedHabit != nil {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                HabitDragState.shared.targetIndex = nil
                HabitDragState.shared.isTargetingHour = false
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
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
        if let habit = HabitDragState.shared.draggedHabit {
            guard listTitle == HabitTaskLink.hourInterval else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    HabitDragState.shared.reset()
                }
                return false
            }
            let descriptor = FetchDescriptor<TaskItem>()
            let allTasks = (try? context.fetch(descriptor)) ?? []
            let alreadyInHour = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
            guard !alreadyInHour else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    HabitDragState.shared.reset()
                }
                return false
            }
            
            let targetIdx = HabitDragState.shared.targetIndex ?? 0
            insertHabitAsTask(habit: habit, at: .atIndex(targetIdx), listTitle: listTitle, context: context)
            withAnimation(.easeInOut(duration: 0.15)) {
                HabitDragState.shared.reset()
            }
            return true
        }
        
        // Handle regular task drop
        if let draggedItem = DragState.shared.draggedTask {
            draggedItem.updatedAt = Date()
        }
        try? context.save()
        SupabaseSyncManager.shared.push()
        withAnimation(.easeInOut(duration: 0.15)) {
            DragState.shared.reset()
        }
        return true
    }
}
