import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TaskListView: View {
    let title: String
    let fontSize: CGFloat
    let tasks: [TaskItem]
    @FocusState.Binding var focusedTaskId: String?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .light, design: .default))
                .tracking(2.0)
                .foregroundColor(.gray)
                .padding(.bottom, 5)
            
            ForEach(tasks) { task in
                TaskRowView(task: task, fontSize: fontSize, isNew: false, listTitle: title, focusedTaskId: $focusedTaskId)
            }
            
            if tasks.isEmpty {
                TaskRowView(task: TaskItem(text: "", intervalType: title), fontSize: fontSize, isNew: true, listTitle: title, focusedTaskId: $focusedTaskId)
            }
        }
        .padding(.bottom, 30)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: colorScheme == .dark ? 0.15 : 0.9)),
            alignment: .bottom
        )
        // Add drop destination for dragging to empty lists
        .onDrop(of: [.text], delegate: TaskListDropDelegate(listTitle: title, tasks: tasks))
    }
}

struct TaskListDropDelegate: DropDelegate {
    let listTitle: String
    let tasks: [TaskItem]

    func dropEntered(info: DropInfo) {
        guard let draggedItem = DragState.shared.draggedTask else { return }
        if draggedItem.intervalType != listTitle && tasks.isEmpty {
            draggedItem.intervalType = listTitle
            draggedItem.order = 0
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        DragState.shared.draggedTask = nil
        return true
    }
}
