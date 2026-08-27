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

    @State private var isPlusHovered: Bool = false

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
            
            ForEach(tasks) { task in
                TaskRowView(task: task, fontSize: fontSize, isNew: false, listTitle: title, focusedTaskId: $focusedTaskId)
            }
            
            if tasks.isEmpty {
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
/// in the 1 Hour list. Only works when listTitle == "1 Hour".
@MainActor
func insertHabitAsTask(habit: HabitItem, at position: HabitInsertPosition, listTitle: String, context: ModelContext) {
    guard listTitle == HabitTaskLink.hourInterval else { return }
    
    let descriptor = FetchDescriptor<TaskItem>()
    guard let allTasks = try? context.fetch(descriptor) else { return }
    
    var sorted = allTasks.filter { $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
    let now = Date()
    
    // If the habit task already exists in the 1 Hour list, reposition it to the requested location
    if let existingTask = sorted.first(where: { $0.habitId == habit.id }) {
        if let currentIdx = sorted.firstIndex(where: { $0.id == existingTask.id }) {
            sorted.remove(at: currentIdx)
        }
        switch position {
        case .top:
            sorted.insert(existingTask, at: 0)
        case .bottom:
            sorted.append(existingTask)
        case .atIndex(let idx):
            let clamped = min(idx, sorted.count)
            sorted.insert(existingTask, at: clamped)
        }
        for (i, t) in sorted.enumerated() {
            t.order = i
        }
        existingTask.updatedAt = now
        try? context.save()
        SupabaseSyncManager.shared.push()
        return
    }
    
    // Otherwise create a new TaskItem linked to the habit
    let newTask = TaskItem(text: habit.text, intervalType: HabitTaskLink.hourInterval, order: 0, habitId: habit.id)
    newTask.updatedAt = now
    context.insert(newTask)
    
    switch position {
    case .top:
        sorted.insert(newTask, at: 0)
    case .bottom:
        sorted.append(newTask)
    case .atIndex(let idx):
        let clamped = min(idx, sorted.count)
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
        // Habit drag visual feedback is handled by dropUpdated
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Allow habit drops only into 1 Hour
        if HabitDragState.shared.draggedHabit != nil && listTitle != HabitTaskLink.hourInterval {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Handle habit drop into 1 Hour
        if let habit = HabitDragState.shared.draggedHabit {
            guard listTitle == HabitTaskLink.hourInterval else { return false }
            insertHabitAsTask(habit: habit, at: .top, listTitle: listTitle, context: context)
            HabitDragState.shared.draggedHabit = nil
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
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if HabitDragState.shared.draggedHabit != nil && listTitle != HabitTaskLink.hourInterval {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Handle habit drop into 1 Hour
        if let habit = HabitDragState.shared.draggedHabit {
            guard listTitle == HabitTaskLink.hourInterval else { return false }
            insertHabitAsTask(habit: habit, at: .bottom, listTitle: listTitle, context: context)
            HabitDragState.shared.draggedHabit = nil
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
