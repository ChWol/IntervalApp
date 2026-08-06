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
    
    @State private var text: String = ""
    @State private var isHovering: Bool = false
    @State private var swipeOffset: CGFloat = 0
    @ObservedObject private var dragState = DragState.shared
    
    private var isDragged: Bool {
        !isNew && dragState.draggedTask?.id == task.id
    }
    
    var body: some View {
        ZStack {
            #if os(iOS)
            // Background reveal for swipe-to-delete on iOS
            if swipeOffset < 0 && !isNew {
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .light))
                        Text("Delete")
                            .font(.system(size: 12, weight: .light))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(maxHeight: .infinity)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(6)
                }
            }
            #endif
            
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
            .offset(x: swipeOffset)
            #if os(iOS)
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { gesture in
                        if !isNew && gesture.translation.width < 0 {
                            swipeOffset = gesture.translation.width
                        }
                    }
                    .onEnded { gesture in
                        if !isNew {
                            if gesture.translation.width < -70 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    swipeOffset = -400
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    task.deletedAt = Date()
                                    task.updatedAt = Date()
                                    try? modelContext.save()
                                    SupabaseSyncManager.shared.push()
                                }
                            } else {
                                withAnimation(.spring()) {
                                    swipeOffset = 0
                                }
                            }
                        }
                    }
            )
            #endif
        }
        .onDrag {
            if !isNew && !text.isEmpty {
                task.text = text
            }
            dragState.draggedTask = task
            dragState.targetIntervalType = listTitle
            dragState.targetFontSize = fontSize
            return NSItemProvider(item: task.id as NSString, typeIdentifier: UTType.data.identifier)
        } preview: {
            let activeFontSize = dragState.targetFontSize
            let displayText = task.text.isEmpty ? (text.isEmpty ? "Task" : text) : task.text
            HStack(spacing: 12) {
                Text("–")
                    .font(.system(size: activeFontSize * 0.8, weight: .light))
                    .foregroundColor(.secondary)
                Text(displayText)
                    .font(.system(size: activeFontSize, weight: .light))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, max(8, activeFontSize * 0.4))
            .padding(.vertical, max(4, activeFontSize * 0.2))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95))
            )
        }
        .onDrop(of: [UTType.data], delegate: TaskDropDelegate(item: task, sectionFontSize: fontSize, context: modelContext))
    }
    
    private var rowContent: some View {
        HStack(alignment: .center, spacing: max(6, fontSize * 0.4)) {
            // Dash prefix or Checkbox
            if isNew {
                Text("–")
                    .font(.system(size: fontSize * 0.8, weight: .light))
                    .foregroundColor(.secondary)
            } else {
                Button(action: {
                    withAnimation {
                        task.completed.toggle()
                        task.completedAt = task.completed ? Date() : nil
                        task.updatedAt = Date()
                        try? modelContext.save()
                        SupabaseSyncManager.shared.push()
                    }
                }) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: fontSize * 0.85, weight: .light))
                        .foregroundColor(task.completed ? .secondary : .primary)
                }
                .buttonStyle(.plain)
            }
            
            // Editable Text Area
            ZStack(alignment: .leading) {
                if isNew && text.isEmpty {
                    Text("Add task...")
                        .font(.system(size: fontSize, weight: .light))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                CustomTextField(
                    text: $text,
                    isFocused: focusedTaskId == (isNew ? "NEW_\(listTitle)" : task.id),
                    onFocusChanged: { focused in
                        if focused {
                            focusedTaskId = isNew ? "NEW_\(listTitle)" : task.id
                        } else {
                            if focusedTaskId == (isNew ? "NEW_\(listTitle)" : task.id) {
                                focusedTaskId = nil
                            }
                            if !isNew {
                                let trimmed = text.trimmingCharacters(in: .whitespaces)
                                if trimmed.isEmpty {
                                    // RULE 1: Soft-delete empty text entries on focus loss & push to Supabase!
                                    task.deletedAt = Date()
                                    task.updatedAt = Date()
                                    try? modelContext.save()
                                    SupabaseSyncManager.shared.push()
                                } else if task.text != trimmed {
                                    task.text = trimmed
                                    task.updatedAt = Date()
                                    try? modelContext.save()
                                    SupabaseSyncManager.shared.pushDebounced()
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
                                    
                                    let nextTask = TaskItem(text: "", intervalType: listTitle, order: newTask.order + 1)
                                    modelContext.insert(nextTask)
                                    
                                    try? modelContext.save()
                                    SupabaseSyncManager.shared.push()
                                    
                                    text = ""
                                    DispatchQueue.main.async {
                                        focusedTaskId = nextTask.id
                                    }
                                }
                            }
                        } else {
                            let trimmed = text.trimmingCharacters(in: .whitespaces)
                            if trimmed.isEmpty {
                                task.deletedAt = Date()
                                task.updatedAt = Date()
                                try? modelContext.save()
                                SupabaseSyncManager.shared.push()
                            } else {
                                task.text = trimmed
                                task.updatedAt = Date()
                                
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
                                    
                                    let now = Date()
                                    for (i, t) in sorted.enumerated() {
                                        t.order = i
                                        t.updatedAt = now
                                    }
                                    
                                    try? modelContext.save()
                                    SupabaseSyncManager.shared.push()
                                    
                                    DispatchQueue.main.async {
                                        focusedTaskId = newTask.id
                                    }
                                }
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
                            task.updatedAt = Date()
                            try? modelContext.save()
                            SupabaseSyncManager.shared.push()
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
                        task.updatedAt = Date()
                        try? modelContext.save()
                        SupabaseSyncManager.shared.push()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: max(fontSize * 0.4, 11), weight: .light))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity((focusedTaskId == task.id || isHovering) ? 1 : 0)
                .padding(.trailing, 6)
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
        }
        .onChange(of: text) { _, newText in
            if !isNew && newText != task.text {
                task.text = newText
                task.updatedAt = Date()
                try? modelContext.save()
                SupabaseSyncManager.shared.pushDebounced()
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
            } else {
                stopMonitoring()
            }
        }
    }
    @Published var dragPosition: CGPoint = .zero
    @Published var targetIntervalType: String?
    @Published var targetFontSize: CGFloat = 20.0
    
    private var monitor: Any?
    
    func reset() {
        draggedTask = nil
        targetIntervalType = nil
        stopMonitoring()
    }
    
    private func startMonitoring() {
        // Auto reset safety timer: if drag hangs for > 3 seconds, force reset to eliminate grey box
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            if self.draggedTask != nil {
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.reset()
                }
            }
        }
        
        #if os(macOS)
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self = self else { return event }
                
                if event.type == .leftMouseUp {
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            self.reset()
                        }
                    }
                } else if event.type == .leftMouseDragged {
                    if let window = event.window {
                        let loc = event.locationInWindow
                        let flippedY = window.frame.height - loc.y
                        DispatchQueue.main.async {
                            self.dragPosition = CGPoint(x: loc.x, y: flippedY)
                        }
                    }
                }
                return event
            }
        }
        #endif
    }
    
    private func stopMonitoring() {
        #if os(macOS)
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        #endif
    }
}

// MARK: - Drop Delegates

struct TaskDropDelegate: DropDelegate {
    let item: TaskItem
    let sectionFontSize: CGFloat
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let draggedItem = DragState.shared.draggedTask else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            DragState.shared.targetIntervalType = item.intervalType
            DragState.shared.targetFontSize = sectionFontSize
            
            if draggedItem.id != item.id {
                draggedItem.intervalType = item.intervalType
                
                let descriptor = FetchDescriptor<TaskItem>()
                guard let allTasks = try? context.fetch(descriptor) else { return }
                var sorted = allTasks.filter { $0.intervalType == item.intervalType && $0.deletedAt == nil && !$0.completed && $0.id != draggedItem.id }.sorted { $0.order < $1.order }
                
                if let targetIdx = sorted.firstIndex(where: { $0.id == item.id }) {
                    sorted.insert(draggedItem, at: targetIdx)
                } else {
                    sorted.append(draggedItem)
                }
                
                let now = Date()
                for (i, t) in sorted.enumerated() {
                    t.order = i
                    t.updatedAt = now
                }
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func dropExited(info: DropInfo) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.15)) {
                DragState.shared.reset()
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        try? context.save()
        SupabaseSyncManager.shared.push()
        withAnimation(.easeInOut(duration: 0.15)) {
            DragState.shared.reset()
        }
        return true
    }
}
