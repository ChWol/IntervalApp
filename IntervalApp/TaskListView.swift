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
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(isPlusHovered ? .primary : .secondary.opacity(0.6))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isPlusHovered = hovering
                }
            }
            .padding(.bottom, 5)
            .contentShape(Rectangle())
            .onDrop(of: [.data], delegate: TaskListHeaderDropDelegate(listTitle: title, sectionFontSize: fontSize, context: modelContext))
            
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
                .onDrop(of: [.data], delegate: TaskListBottomDropDelegate(listTitle: title, sectionFontSize: fontSize, context: modelContext))
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

// MARK: - List Drop Delegates

struct TaskListHeaderDropDelegate: DropDelegate {
    let listTitle: String
    let sectionFontSize: CGFloat
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let draggedItem = DragState.shared.draggedTask else { return }
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
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        let descriptor = FetchDescriptor<TaskItem>()
        if let allTasks = try? context.fetch(descriptor) {
            let now = Date()
            for task in allTasks {
                task.updatedAt = now
            }
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
        guard let draggedItem = DragState.shared.draggedTask else { return }
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
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        let descriptor = FetchDescriptor<TaskItem>()
        if let allTasks = try? context.fetch(descriptor) {
            let now = Date()
            for task in allTasks {
                task.updatedAt = now
            }
        }
        try? context.save()
        SupabaseSyncManager.shared.push()
        withAnimation(.easeInOut(duration: 0.15)) {
            DragState.shared.reset()
        }
        return true
    }
}
