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
    @State private var isXHovered: Bool = false
    @State private var isCheckmarkHovering: Bool = false
    @State private var localCompleted: Bool = false
    @State private var isExpanded: Bool = false
    @State private var swipeOffset: CGFloat = 0
    @ObservedObject private var dragState = DragState.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    
    private var isDragged: Bool {
        !isNew && dragState.draggedTask?.id == task.id
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            #if os(iOS)
            // Permanent background action layer (Trash icon button revealed dynamically on drag)
            if !isNew {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        swipeOffset = 0
                        TaskHousekeeping.moveToBin(task, in: modelContext)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: max(fontSize * 0.7, 13), weight: .light))
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: max(fontSize * 1.4, 30))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(min(1.0, max(0.0, Double(-swipeOffset) / 20.0)))
                .scaleEffect(min(1.0, max(0.6, Double(-swipeOffset) / 40.0)))
                .padding(.trailing, 4)
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
            .background(Color(colorScheme == .dark ? .black : .white))
            .offset(x: swipeOffset)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.85), value: swipeOffset)
            #if os(iOS)
            .gesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { gesture in
                        if !isNew {
                            let translation = gesture.translation.width
                            if translation < 0 {
                                swipeOffset = max(translation, -65)
                            } else if swipeOffset < 0 {
                                swipeOffset = min(0, -50 + translation)
                            }
                        }
                    }
                    .onEnded { gesture in
                        if !isNew {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                if swipeOffset < -25 {
                                    swipeOffset = -50 // Reveal trash icon button smoothly
                                } else {
                                    swipeOffset = 0
                                }
                            }
                        }
                    }
            )
            #endif
        }
        .onChange(of: focusedTaskId) { _, newId in
            let myId = isNew ? "NEW_\(listTitle)" : task.id
            if newId != myId {
                if isExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = false
                    }
                }
                if swipeOffset != 0 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        swipeOffset = 0
                    }
                }
            }
        }
        #if os(macOS)
        .onDrag {
            if !isNew && !text.isEmpty && task.text != text {
                task.text = text
                task.updatedAt = Date()
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
                    .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            )
        }
        .onDrop(of: [UTType.data], delegate: TaskDropDelegate(item: task, sectionFontSize: fontSize, context: modelContext))
        #endif
    }
    
    // MARK: - Normal Row Content with Dash & Checkmark Transition
    
    private var rowContent: some View {
        HStack(alignment: .center, spacing: max(8, fontSize * 0.5)) {
            if !isNew {
                Button(action: {
                    focusedTaskId = nil
                    #if os(iOS)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                    withAnimation(.easeOut(duration: 0.2)) {
                        localCompleted = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation {
                            let now = Date()
                            HabitTaskLink.setTaskCompleted(true, on: task, now: now)
                            // A task created from a habit ticks that habit off too.
                            if task.habitId != nil,
                               let habits = try? modelContext.fetch(FetchDescriptor<HabitItem>()) {
                                HabitTaskLink.applyTaskCompletionToHabit(task, habits: habits, now: now)
                            }
                            try? modelContext.save()
                            SupabaseSyncManager.shared.push()
                        }
                    }
                }) {
                    ZStack {
                        Text("–")
                            .font(.system(size: fontSize * 0.8, weight: .light))
                            .foregroundColor(localCompleted ? .primary : .secondary)
                            .opacity(isCheckmarkHovering || localCompleted ? 0 : 1)
                            .rotationEffect(.degrees(isCheckmarkHovering || localCompleted ? -90 : 0))
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: fontSize * 0.8, weight: .light))
                            .foregroundColor(.primary)
                            .opacity(isCheckmarkHovering || localCompleted ? 1 : 0)
                            .scaleEffect(isCheckmarkHovering || localCompleted ? 1 : 0.5)
                    }
                    .frame(width: max(15, fontSize * 0.9), alignment: .center)
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
                    .foregroundColor(.secondary)
                    .frame(width: max(15, fontSize * 0.9), alignment: .center)
            }
            
            if localCompleted {
                Text(task.text)
                    .font(.system(size: fontSize, weight: .light))
                    .foregroundColor(.secondary)
                    .strikethrough(true)
                    .lineLimit(isExpanded ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
            } else {
                let myId = isNew ? "NEW_\(listTitle)" : task.id
                let isCurrentlyFocused = (focusedTaskId == myId)
                
                ZStack(alignment: .leading) {
                    if isCurrentlyFocused {
                        CustomTextField(
                            text: $text,
                            isFocused: true,
                            onFocusChanged: { focused in
                                if focused {
                                    focusedTaskId = myId
                                } else {
                                    if focusedTaskId == myId {
                                        focusedTaskId = nil
                                    }
                                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                                    if isNew {
                                        if !trimmed.isEmpty {
                                            let descriptor = FetchDescriptor<TaskItem>()
                                            if let all = try? modelContext.fetch(descriptor) {
                                                let sorted = all.filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                                                let newTask = TaskItem(text: trimmed, intervalType: listTitle, order: (sorted.last?.order ?? 0) + 1)
                                                modelContext.insert(newTask)
                                                try? modelContext.save()
                                                SupabaseSyncManager.shared.push()
                                                text = ""
                                            }
                                        }
                                    } else {
                                        if trimmed.isEmpty {
                                            TaskHousekeeping.moveToBin(task, in: modelContext)
                                        } else if task.text != trimmed {
                                            task.text = trimmed
                                            task.updatedAt = Date()
                                            try? modelContext.save()
                                            SupabaseSyncManager.shared.push()
                                        }
                                    }
                                }
                            },
                            onSubmit: { isAtBeginning in
                                if isNew {
                                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                                    if !trimmed.isEmpty {
                                        let descriptor = FetchDescriptor<TaskItem>()
                                        if let all = try? modelContext.fetch(descriptor) {
                                            let sorted = all.filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                                            let newTask = TaskItem(text: trimmed, intervalType: listTitle, order: (sorted.last?.order ?? 0) + 1)
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
                                        TaskHousekeeping.moveToBin(task, in: modelContext)
                                    } else {
                                        task.text = trimmed
                                        task.updatedAt = Date()
                                        
                                        let descriptor = FetchDescriptor<TaskItem>()
                                        if let all = try? modelContext.fetch(descriptor) {
                                            var sorted = all.filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                                            let newTask = TaskItem(text: "", intervalType: listTitle, order: task.order)
                                            modelContext.insert(newTask)
                                            
                                            if let idx = sorted.firstIndex(where: { $0.id == task.id }) {
                                                if isAtBeginning {
                                                    sorted.insert(newTask, at: idx)
                                                } else {
                                                    sorted.insert(newTask, at: idx + 1)
                                                }
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
                                    TaskHousekeeping.moveToBin(task, in: modelContext)
                                }
                            },
                            fontSize: fontSize,
                            placeholder: isNew ? "Add task...".localized : ""
                        )
                    } else {
                        let rawText = isNew ? text : (text.isEmpty ? task.text : text)
                        let displayText = rawText.isEmpty ? (isNew ? "Add task...".localized : "") : rawText
                        let isPlaceholder = isNew && rawText.isEmpty
                        
                        Text(displayText)
                            .font(.system(size: fontSize, weight: .light))
                            .foregroundColor(isPlaceholder ? .secondary.opacity(0.5) : .primary)
                            .lineLimit(isExpanded ? nil : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isNew {
                                    focusedTaskId = myId
                                } else {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if !isExpanded {
                                            focusedTaskId = myId
                                            isExpanded = true
                                        } else {
                                            focusedTaskId = myId
                                        }
                                    }
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if !isNew {
                Button(action: {
                    withAnimation {
                        TaskHousekeeping.moveToBin(task, in: modelContext)
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: max(fontSize * 0.4, 11), weight: .light))
                        .foregroundColor(isXHovered ? .primary : .secondary.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isXHovered = hovering
                    if hovering { isHovering = true }
                }
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
        .onDisappear {
            // Flush any pending text edits immediately when scrolling off-screen
            if !isNew && text != task.text {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    task.text = trimmed
                    task.updatedAt = Date()
                    try? modelContext.save()
                    SupabaseSyncManager.shared.push()
                }
            }
        }
        .onChange(of: task.text) { _, newText in
            // Pick up remote changes from pull sync
            if !isNew && text != newText {
                text = newText
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
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            DragState.shared.targetIntervalType = item.intervalType
            DragState.shared.targetFontSize = sectionFontSize
            
            if draggedItem.id != item.id || draggedItem.intervalType != item.intervalType {
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
