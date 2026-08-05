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

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Category Header: Drop here to place at top of list
            Text(title.uppercased())
                .font(.system(size: 10, weight: .light, design: .default))
                .tracking(2.0)
                .foregroundColor(.gray)
                .padding(.bottom, 5)
                .contentShape(Rectangle())
                .onDrop(of: [.text], delegate: TaskListHeaderDropDelegate(listTitle: title, context: modelContext))
            
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
                .onDrop(of: [.text], delegate: TaskListBottomDropDelegate(listTitle: title, context: modelContext))
        }
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: colorScheme == .dark ? 0.15 : 0.9)),
            alignment: .bottom
        )
    }
}

// MARK: - List Drop Delegates

struct TaskListHeaderDropDelegate: DropDelegate {
    let listTitle: String
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let draggedItem = DragState.shared.draggedTask else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
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
        withAnimation(.easeInOut(duration: 0.15)) {
            DragState.shared.draggedTask = nil
        }
        return true
    }
}

struct TaskListBottomDropDelegate: DropDelegate {
    let listTitle: String
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let draggedItem = DragState.shared.draggedTask else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
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
        withAnimation(.easeInOut(duration: 0.15)) {
            DragState.shared.draggedTask = nil
        }
        return true
    }
}
