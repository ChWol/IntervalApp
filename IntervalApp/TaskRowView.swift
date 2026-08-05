import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TaskRowView: View {
    @Bindable var task: TaskItem
    let fontSize: CGFloat
    let isNew: Bool
    let listTitle: String
    
    @Environment(\.modelContext) private var modelContext
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
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
                .focused($isFocused)
                .onSubmit {
                    if isNew {
                        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                            let newTask = TaskItem(text: text, intervalType: listTitle)
                            modelContext.insert(newTask)
                            text = ""
                        }
                    } else {
                        let descriptor = FetchDescriptor<TaskItem>()
                        if let all = try? modelContext.fetch(descriptor) {
                            for t in all where t.intervalType == listTitle && t.order > task.order {
                                t.order += 1
                            }
                        }
                        let newTask = TaskItem(text: "", intervalType: listTitle, order: task.order + 1)
                        modelContext.insert(newTask)
                    }
                }
                .onChange(of: isFocused) { focused in
                    if !focused {
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
                .opacity((isFocused || isHovering) ? 1 : 0)
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
            if !isNew && task.text.isEmpty {
                isFocused = true
            }
        }
        .onDrag {
            DragState.shared.draggedTask = task
            return NSItemProvider(object: task.id as NSString)
        }
        .onDrop(of: [.text], delegate: TaskDropDelegate(item: task))
    }
}

class DragState {
    static let shared = DragState()
    var draggedTask: TaskItem?
}

struct TaskDropDelegate: DropDelegate {
    let item: TaskItem

    func dropEntered(info: DropInfo) {
        guard let draggedItem = DragState.shared.draggedTask else { return }
        if draggedItem.id != item.id {
            // Live reordering swap
            let draggedOrder = draggedItem.order
            draggedItem.order = item.order
            item.order = draggedOrder
            
            if draggedItem.intervalType != item.intervalType {
                draggedItem.intervalType = item.intervalType
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
