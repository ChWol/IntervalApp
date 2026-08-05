import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TaskRowView: View {
    @Bindable var task: TaskItem
    let fontSize: CGFloat
    let isNew: Bool
    let listTitle: String
    @FocusState.Binding var focusedTaskId: String?
    
    @Environment(\.modelContext) private var modelContext
    @State private var text: String = ""
    @State private var isHovering: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            if !isNew {
                Button(action: {
                    withAnimation {
                        task.completed.toggle()
                        task.completedAt = task.completed ? Date() : nil
                    }
                }) {
                    Text("–")
                        .font(.system(size: fontSize * 0.8, weight: .light))
                        .foregroundColor(task.completed ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text("–")
                    .font(.system(size: fontSize * 0.8, weight: .light))
                    .opacity(0)
            }
            
            TextField(isNew ? "Add task..." : "", text: $text)
                .font(.system(size: fontSize, weight: .light))
                .foregroundColor(task.completed ? .secondary : .primary)
                .strikethrough(task.completed)
                .textFieldStyle(.plain)
                .focused($focusedTaskId, equals: task.id)
                .onKeyPress(.delete) {
                    if text.trimmingCharacters(in: .whitespaces).isEmpty && !isNew {
                        let descriptor = FetchDescriptor<TaskItem>()
                        if let all = try? modelContext.fetch(descriptor) {
                            let sorted = all.filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                            if let idx = sorted.firstIndex(where: { $0.id == task.id }), idx > 0 {
                                focusedTaskId = sorted[idx - 1].id
                            }
                        }
                        task.deletedAt = Date()
                        return .handled
                    }
                    return .ignored
                }
                .onSubmit {
                    if isNew {
                        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                            let descriptor = FetchDescriptor<TaskItem>()
                            if let all = try? modelContext.fetch(descriptor) {
                                let sorted = all.filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                                let newTask = TaskItem(text: text, intervalType: listTitle, order: (sorted.last?.order ?? 0) + 1)
                                modelContext.insert(newTask)
                            }
                            text = ""
                        }
                    } else {
                        let descriptor = FetchDescriptor<TaskItem>()
                        if let all = try? modelContext.fetch(descriptor) {
                            var sorted = all.filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                            let newTask = TaskItem(text: "", intervalType: listTitle, order: task.order)
                            modelContext.insert(newTask)
                            
                            if let idx = sorted.firstIndex(where: { $0.id == task.id }) {
                                sorted.insert(newTask, at: idx + 1)
                            } else {
                                sorted.append(newTask)
                            }
                            
                            for (i, t) in sorted.enumerated() {
                                t.order = i
                            }
                            
                            // Immediately focus the new row
                            focusedTaskId = newTask.id
                        }
                    }
                }
                .onChange(of: focusedTaskId) { oldId, newId in
                    if oldId == task.id && newId != task.id { // Just lost focus
                        if isNew {
                            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                                let newTask = TaskItem(text: text, intervalType: listTitle)
                                modelContext.insert(newTask)
                                text = ""
                            }
                        } else {
                            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                                task.deletedAt = Date()
                            } else {
                                task.text = text
                            }
                        }
                    }
                }
            
            if !isNew {
                Button(action: {
                    withAnimation {
                        task.deletedAt = Date()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: fontSize * 0.4))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity((focusedTaskId == task.id || isHovering) ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            if !isNew {
                text = task.text
            }
            if !isNew && task.text.isEmpty && focusedTaskId == nil {
                focusedTaskId = task.id
            }
        }
        .onDrag {
            DragState.shared.draggedTask = task
            return NSItemProvider(object: task.id as NSString)
        }
        .onDrop(of: [.text], delegate: TaskDropDelegate(item: task, context: modelContext))
    }
}

class DragState {
    static let shared = DragState()
    var draggedTask: TaskItem?
}

struct TaskDropDelegate: DropDelegate {
    let item: TaskItem
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let draggedItem = DragState.shared.draggedTask else { return }
        if draggedItem.id != item.id {
            draggedItem.intervalType = item.intervalType
            
            // Recalculate orders cleanly to prevent duplicate/skipped orders
            let descriptor = FetchDescriptor<TaskItem>()
            guard let allTasks = try? context.fetch(descriptor) else { return }
            var sorted = allTasks.filter { $0.intervalType == item.intervalType && $0.deletedAt == nil && !$0.completed && $0.id != draggedItem.id }.sorted { $0.order < $1.order }
            
            if let targetIdx = sorted.firstIndex(where: { $0.id == item.id }) {
                sorted.insert(draggedItem, at: targetIdx)
            } else {
                sorted.append(draggedItem)
            }
            
            for (i, t) in sorted.enumerated() {
                t.order = i
            }
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
