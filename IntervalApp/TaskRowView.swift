import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine

struct TaskRowView: View {
    @Bindable var task: TaskItem
    let fontSize: CGFloat
    let isNew: Bool
    let listTitle: String
    @Binding var focusedTaskId: String?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var dragState = DragState.shared
    @State private var text: String = ""
    @State private var isHovering: Bool = false
    @State private var isCheckmarkHovering: Bool = false
    @State private var localCompleted: Bool = false
    
    private var isDragged: Bool {
        !isNew && dragState.draggedTask?.id == task.id
    }
    
    var body: some View {
        ZStack {
            if isDragged {
                // Sleek grey box placeholder for the insertion slot
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .frame(height: max(fontSize * 1.2, 24))
            }
            
            rowContent
                .opacity(isDragged ? 0 : 1)
        }
        .onDrag {
            // Ensure task.text is flushed before drag starts
            if !isNew && !text.isEmpty {
                task.text = text
            }
            dragState.draggedTask = task
            return NSItemProvider(object: task.id as NSString)
        } preview: {
            // Optimized minimal floating preview card
            let displayText = task.text.isEmpty ? (text.isEmpty ? "Task" : text) : task.text
            HStack(spacing: 12) {
                Text("–")
                    .font(.system(size: fontSize * 0.8, weight: .light))
                    .foregroundColor(.secondary)
                Text(displayText)
                    .font(.system(size: fontSize, weight: .light))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            )
        }
        .onDrop(of: [.text], delegate: TaskDropDelegate(item: task, context: modelContext))
        .onChange(of: text) { _, newValue in
            if !isNew && !newValue.isEmpty {
                task.text = newValue
            }
        }
    }
    
    // MARK: - Normal Row Content
    
    private var rowContent: some View {
        HStack(alignment: .center, spacing: 15) {
            if !isNew {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        localCompleted = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation {
                            task.completed = true
                            task.completedAt = Date()
                        }
                    }
                }) {
                    ZStack {
                        Text("–")
                            .font(.system(size: fontSize * 0.8, weight: .light))
                            .foregroundColor(localCompleted ? .primary : .secondary)
                            .opacity(isCheckmarkHovering ? 0 : 1)
                            .rotationEffect(.degrees(isCheckmarkHovering ? -90 : 0))
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: fontSize * 0.8, weight: .light))
                            .foregroundColor(.primary)
                            .opacity(isCheckmarkHovering ? 1 : 0)
                            .scaleEffect(isCheckmarkHovering ? 1 : 0.5)
                    }
                    .frame(width: 15, alignment: .center)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCheckmarkHovering = hovering
                    }
                }
            } else {
                Text("–")
                    .font(.system(size: fontSize * 0.8, weight: .light))
                    .frame(width: 15, alignment: .center)
                    .opacity(0)
            }
            
            if localCompleted {
                Text(task.text)
                    .font(.system(size: fontSize, weight: .light))
                    .foregroundColor(.secondary)
                    .strikethrough(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                CustomTextField(
                    text: $text,
                    isFocused: focusedTaskId == task.id,
                    onFocusChanged: { focused in
                        if focused {
                            focusedTaskId = task.id
                        } else {
                            if focusedTaskId == task.id {
                                focusedTaskId = nil
                            }
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
                    },
                    onSubmit: {
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
                            task.text = text
                            
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
                                
                                focusedTaskId = newTask.id
                            }
                        }
                    },
                    onDeleteEmpty: {
                        if !isNew {
                            let descriptor = FetchDescriptor<TaskItem>()
                            if let all = try? modelContext.fetch(descriptor) {
                                let sorted = all.filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                                if let idx = sorted.firstIndex(where: { $0.id == task.id }), idx > 0 {
                                    focusedTaskId = sorted[idx - 1].id
                                }
                            }
                            task.deletedAt = Date()
                        }
                    },
                    fontSize: fontSize,
                    placeholder: isNew ? "Add task..." : ""
                )
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
                .padding(.trailing, 10)
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
                focusedTaskId = task.id
            }
        }
    }
}

// MARK: - Drag State

class DragState: ObservableObject {
    static let shared = DragState()
    @Published var draggedTask: TaskItem? {
        didSet {
            if draggedTask != nil {
                startMonitoring()
            }
        }
    }
    
    private var monitor: Any?
    
    private func startMonitoring() {
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self?.draggedTask = nil
                    }
                }
                self?.stopMonitoring()
                return event
            }
        }
    }
    
    private func stopMonitoring() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

// MARK: - Drop Delegates

struct TaskDropDelegate: DropDelegate {
    let item: TaskItem
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let draggedItem = DragState.shared.draggedTask else { return }
        if draggedItem.id != item.id {
            withAnimation(.easeInOut(duration: 0.2)) {
                draggedItem.intervalType = item.intervalType
                
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
