#if !os(watchOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine

struct TaskRowView: View {
    @Bindable var task: TaskItem
    let fontSize: CGFloat
    let isNew: Bool
    let listTitle: String
    var onDeepFocus: ((TaskItem) -> Void)? = nil
    
    @Binding var focusedTaskId: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    
    @State private var text: String = ""
    @State private var isHovering: Bool = false
    @State private var isXHovered: Bool = false
    @State private var isCheckmarkHovering: Bool = false
    @State private var isDeepFocusHovered: Bool = false
    @State private var localCompleted: Bool = false
    @State private var isExpanded: Bool = false
    @State private var swipeOffset: CGFloat = 0
    @ObservedObject private var dragState = DragState.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    
    private var isDragged: Bool {
        #if os(iOS)
        // Keep the source readable throughout the native touch drag. UIKit can
        // finish a cancelled drag without calling any SwiftUI drop delegate.
        return false
        #else
        !isNew && dragState.draggedTask?.id == task.id && dragState.targetIndex != nil
        #endif
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { gesture in
                        if !isNew {
                            let h = gesture.translation.height
                            let w = gesture.translation.width
                            // If the gesture has a strong vertical component, prioritize vertical scrolling
                            if abs(h) > abs(w) * 0.7 {
                                if swipeOffset != 0 {
                                    withAnimation(.interactiveSpring()) {
                                        swipeOffset = 0
                                    }
                                }
                                return
                            }
                            
                            // Dominantly horizontal swipe to reveal delete
                            if w < 0 {
                                swipeOffset = max(w, -65)
                            } else if swipeOffset < 0 {
                                swipeOffset = min(0, -50 + w)
                            }
                        }
                    }
                    .onEnded { gesture in
                        if !isNew {
                            let h = gesture.translation.height
                            let w = gesture.translation.width
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                if abs(h) > abs(w) * 0.7 {
                                    swipeOffset = 0
                                } else if swipeOffset < -25 {
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
        .onChange(of: focusedTaskId) { oldId, newId in
            let myId = isNew ? "NEW_\(listTitle)" : task.id
            if oldId == myId && newId != myId {
                saveTask()
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
        .onReceive(NotificationCenter.default.publisher(for: .flushPendingEdits)) { _ in
            let myId = isNew ? "NEW_\(listTitle)" : task.id
            if focusedTaskId == myId {
                saveTask()
            }
        }
        .id(isNew ? "NEW_\(listTitle)" : task.id)
        // SwiftUI uses the same drag interaction on macOS and iPhone. On
        // iPhone this starts after a long press; the drop delegates below
        // preserve the same ordering rules as the Mac implementation.
        .onDrag {
            if !isNew && !text.isEmpty && task.text != text {
                task.text = text
                task.updatedAt = Date()
            }
            guard !isNew else { return NSItemProvider() }
            dragState.begin(task, interval: listTitle, fontSize: fontSize)
            return NSItemProvider(object: task.id as NSString)
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
        .onDrop(of: [UTType.data, UTType.plainText, UTType.text], delegate: TaskDropDelegate(item: task, sectionFontSize: fontSize, context: modelContext))
        .contextMenu {
            if !isNew, let onDeepFocus {
                Button {
                    focusedTaskId = nil
                    onDeepFocus(task)
                } label: {
                    Label("Deep Focus", systemImage: "viewfinder")
                }
            }
        }
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
                    SoundManager.playTaskCompleted()
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
                            _ = PersistenceSafety.save(modelContext)
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
                Text(LinkTaskText.displayText(for: task.text))
                    .font(.system(size: fontSize, weight: .light))
                    .foregroundColor(.secondary)
                    .strikethrough(true)
                    .lineLimit(isExpanded ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = LinkTaskText.parts(in: task.text)?.url ?? LinkTaskText.validURL(task.text) {
                            openURL(url)
                            return
                        }
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
                                    saveTask()
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
                                            
                                            _ = PersistenceSafety.save(modelContext)
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
                                        // Silent bin – empty row submission must NOT play delete sound
                                        task.deletedAt = Date()
                                        task.updatedAt = Date()
                                        _ = PersistenceSafety.save(modelContext)
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
                                            
                                            _ = PersistenceSafety.save(modelContext)
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
                                    // Silent bin – empty row deletion by backspace/delete must NOT play delete sound
                                    task.deletedAt = Date()
                                    task.updatedAt = Date()
                                    _ = PersistenceSafety.save(modelContext)
                                    SupabaseSyncManager.shared.push()
                                }
                            },
                            onPasteMultipleLines: { lines in
                                handleMultiLinePaste(lines: lines)
                            },
                            onTab: {
                                saveTask()
                                NotificationCenter.default.post(
                                    name: .focusNextTask,
                                    object: nil,
                                    userInfo: ["currentId": myId, "direction": "forward"]
                                )
                            },
                            onBacktab: {
                                saveTask()
                                NotificationCenter.default.post(
                                    name: .focusNextTask,
                                    object: nil,
                                    userInfo: ["currentId": myId, "direction": "backward"]
                                )
                            },
                            fontSize: fontSize,
                            placeholder: isNew ? "Add task...".localized : ""
                        )
                    } else {
                        let rawText = isNew ? text : (text.isEmpty ? task.text : text)
                        let displayText = rawText.isEmpty ? (isNew ? "Add task...".localized : "") : rawText
                        let isPlaceholder = isNew && rawText.isEmpty
                        
                        Text(LinkTaskText.displayText(for: displayText))
                            .font(.system(size: fontSize, weight: .light))
                            .foregroundColor(isPlaceholder ? .secondary.opacity(0.5) : .primary)
                            .lineLimit(isExpanded ? nil : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    if LinkTaskText.parts(in: displayText) != nil {
                                        focusedTaskId = myId
                                        isExpanded = true
                                    }
                                }
                            )
                            .onTapGesture {
                                if let url = LinkTaskText.parts(in: displayText)?.url ?? LinkTaskText.validURL(displayText) {
                                    openURL(url)
                                    return
                                }
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
                if let onDeepFocus {
                    Button {
                        focusedTaskId = nil
                        onDeepFocus(task)
                    } label: {
                        Image(systemName: "viewfinder")
                            .font(.system(size: max(fontSize * 0.45, 11), weight: .light))
                            .foregroundColor(isDeepFocusHovered ? .primary : .secondary.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.primary.opacity(isDeepFocusHovered ? 0.1 : 0.04)))
                            .scaleEffect(isDeepFocusHovered ? 1.08 : 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering || focusedTaskId == task.id ? 1 : 0)
                    .onHover { isDeepFocusHovered = $0 }
                    .pointingHandCursor()
                    .help("Deep Focus")
                }
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
                    _ = PersistenceSafety.save(modelContext)
                    SupabaseSyncManager.shared.push()
                    resolveLinkTitleIfNeeded(for: task, submittedText: trimmed)
                }
            }
        }
        .onChange(of: task.text) { _, newText in
            // Pick up remote changes from pull sync ONLY if user is not actively editing this task
            let myId = isNew ? "NEW_\(listTitle)" : task.id
            if !isNew && (focusedTaskId != myId) && text != newText {
                text = newText
            }
        }
        .onChange(of: text) { _, newText in
            if !isNew && newText != task.text {
                task.text = newText
                task.updatedAt = Date()
                _ = PersistenceSafety.save(modelContext)
                SupabaseSyncManager.shared.pushDebounced()
            }
        }
    }
    
    private func saveTask() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if isNew {
            if !trimmed.isEmpty {
                let descriptor = FetchDescriptor<TaskItem>()
                if let all = try? modelContext.fetch(descriptor) {
                    let sorted = all.filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                    let newTask = TaskItem(text: trimmed, intervalType: listTitle, order: (sorted.last?.order ?? -1) + 1)
                    modelContext.insert(newTask)
                    _ = PersistenceSafety.save(modelContext)
                    SupabaseSyncManager.shared.push()
                    text = ""
                    resolveLinkTitleIfNeeded(for: newTask, submittedText: trimmed)
                }
            }
            return
        } else {
            if trimmed.isEmpty {
                // Silent bin – clearing an empty row is housekeeping, not a deliberate deletion
                task.deletedAt = Date()
                task.updatedAt = Date()
                _ = PersistenceSafety.save(modelContext)
                SupabaseSyncManager.shared.push()
            } else if task.text != trimmed {
                task.text = trimmed
                task.updatedAt = Date()
                _ = PersistenceSafety.save(modelContext)
                SupabaseSyncManager.shared.push()
            }
        }
        if !trimmed.isEmpty {
            resolveLinkTitleIfNeeded(for: task, submittedText: trimmed)
        }
    }

    private func resolveLinkTitleIfNeeded(for task: TaskItem, submittedText: String) {
        let trimmed = submittedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = LinkTaskText.validURL(trimmed),
              url.absoluteString == trimmed,
              LinkTaskText.parts(in: trimmed) == nil else { return }

        Task {
            guard let title = await LinkTaskText.fetchTitle(for: url) else { return }
            await MainActor.run {
                // Do not overwrite a newer edit while the page title is loading.
                guard task.text == trimmed else { return }
                task.text = LinkTaskText.storedText(title: title, url: url)
                task.updatedAt = Date()
                _ = PersistenceSafety.save(modelContext)
                SupabaseSyncManager.shared.push()
            }
        }
    }
    
    private func handleMultiLinePaste(lines: [String]) {
        guard lines.count > 1 else { return }
        let trimmedFirst = lines[0].trimmingCharacters(in: .whitespaces)
        let rest = Array(lines.dropFirst()).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        let descriptor = FetchDescriptor<TaskItem>()
        guard let allTasks = try? modelContext.fetch(descriptor) else { return }
        let now = Date()
        
        if isNew {
            let sorted = allTasks
                .filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed }
                .sorted { $0.order < $1.order }
            var nextOrder = (sorted.last?.order ?? -1) + 1
            
            if !trimmedFirst.isEmpty {
                let firstTask = TaskItem(text: trimmedFirst, intervalType: listTitle, order: nextOrder)
                modelContext.insert(firstTask)
                nextOrder += 1
            }
            for line in rest {
                let newTask = TaskItem(text: line, intervalType: listTitle, order: nextOrder)
                modelContext.insert(newTask)
                nextOrder += 1
            }
            
            let trailingNewTask = TaskItem(text: "", intervalType: listTitle, order: nextOrder)
            modelContext.insert(trailingNewTask)
            
            _ = PersistenceSafety.save(modelContext)
            SupabaseSyncManager.shared.push()
            
            text = ""
            DispatchQueue.main.async {
                focusedTaskId = trailingNewTask.id
            }
        } else {
            task.text = trimmedFirst
            task.updatedAt = now
            text = trimmedFirst
            
            let sorted = allTasks
                .filter { $0.intervalType == listTitle && $0.deletedAt == nil && !$0.completed }
                .sorted { $0.order < $1.order }
            
            var nextOrder = task.order + 1
            var lastCreatedTask: TaskItem? = nil
            for line in rest {
                let newTask = TaskItem(text: line, intervalType: listTitle, order: nextOrder)
                modelContext.insert(newTask)
                nextOrder += 1
                lastCreatedTask = newTask
            }
            
            let subsequentTasks = sorted.filter { $0.order > task.order && $0.id != task.id }
            for subTask in subsequentTasks {
                subTask.order = nextOrder
                nextOrder += 1
            }
            
            _ = PersistenceSafety.save(modelContext)
            SupabaseSyncManager.shared.push()
            
            if let lastId = lastCreatedTask?.id {
                DispatchQueue.main.async {
                    focusedTaskId = lastId
                }
            }
        }
    }
}

// MARK: - Drag State

@MainActor
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
    @Published var targetIndex: Int?
    @Published var targetFontSize: CGFloat = 20.0
    
    private var monitor: Any?
    private var recoveryGeneration = 0
    private var lastDragActivity = Date.distantPast
    private var recoveryScheduled = false
    private var dragGeneration = 0
    private var targetActivityGeneration = 0

    func begin(_ task: TaskItem, interval: String, fontSize: CGFloat) {
        HabitDragState.shared.reset()
        dragGeneration += 1
        draggedTask = task
        targetIntervalType = interval
        targetIndex = nil
        targetFontSize = fontSize
        noteDragActivity()
    }
    
    func reset() {
        dragGeneration += 1
        targetActivityGeneration += 1
        recoveryGeneration += 1
        recoveryScheduled = false
        draggedTask = nil
        targetIntervalType = nil
        targetIndex = nil
        stopMonitoring()
    }

    func resetAfterDropWindow() {
        let generation = dragGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.dragGeneration == generation else { return }
            self.reset()
        }
    }

    func noteDragActivity() {
        targetActivityGeneration += 1
        #if os(iOS)
        guard draggedTask != nil else { return }
        lastDragActivity = Date()
        guard !recoveryScheduled else { return }
        recoveryScheduled = true
        let generation = recoveryGeneration
        scheduleRecoveryCheck(generation: generation)
        #endif
    }

    func clearTargetAfterExit() {
        #if os(iOS)
        let generation = targetActivityGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.targetActivityGeneration == generation else { return }
            self.targetIndex = nil
        }
        #endif
    }

    private func scheduleRecoveryCheck(generation: Int) {
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.recoveryGeneration == generation else { return }
            if Date().timeIntervalSince(self.lastDragActivity) >= 4 {
                self.reset()
            } else {
                self.scheduleRecoveryCheck(generation: generation)
            }
        }
        #endif
    }
    
    private func startMonitoring() {
        #if os(macOS)
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self = self else { return event }
                
                if event.type == .leftMouseUp {
                    DispatchQueue.main.async {
                        self.resetAfterDropWindow()
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

#if !os(watchOS)
// MARK: - Drop Delegates

struct TaskDropDelegate: DropDelegate {
    let item: TaskItem
    let sectionFontSize: CGFloat
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        DragState.shared.noteDragActivity()
        HabitDragState.shared.noteDragActivity()
        // 1. Handle habit drag entering a task row in 1 Hour
        if let habit = HabitDragState.shared.draggedHabit {
            if item.intervalType == HabitTaskLink.hourInterval {
                let descriptor = FetchDescriptor<TaskItem>()
                let allTasks = (try? context.fetch(descriptor)) ?? []
                let alreadyInHour = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
                if !alreadyInHour {
                    let sorted = allTasks.filter { $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                    let itemIdx = sorted.firstIndex(where: { $0.id == item.id }) ?? 0
                    HabitDragState.shared.targetIndex = itemIdx
                    HabitDragState.shared.isTargetingHour = true
                }
            }
            return
        }
        
        // 2. Handle regular task drag
        updateTaskTarget(info: info)
    }
    
    func dropExited(info: DropInfo) {
        DragState.shared.clearTargetAfterExit()
        HabitDragState.shared.clearTargetAfterExit()
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DragState.shared.noteDragActivity()
        HabitDragState.shared.noteDragActivity()
        // Handle habit drag
        if let habit = HabitDragState.shared.draggedHabit {
            if item.intervalType != HabitTaskLink.hourInterval {
                return DropProposal(operation: .forbidden)
            }
            let descriptor = FetchDescriptor<TaskItem>()
            let allTasks = (try? context.fetch(descriptor)) ?? []
            let alreadyInHour = allTasks.contains { $0.habitId == habit.id && $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }
            if alreadyInHour {
                return DropProposal(operation: .forbidden)
            }
            
            let sorted = allTasks.filter { $0.intervalType == HabitTaskLink.hourInterval && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
            if let itemIdx = sorted.firstIndex(where: { $0.id == item.id }) {
                // If cursor is in the lower half of this task row, place placeholder below it (index + 1)
                let isBottomHalf = info.location.y > (sectionFontSize * 1.5 / 2.0)
                let candidateIdx = isBottomHalf ? itemIdx + 1 : itemIdx
                if HabitDragState.shared.targetIndex != candidateIdx {
                    HabitDragState.shared.targetIndex = candidateIdx
                    HabitDragState.shared.isTargetingHour = true
                }
            }
            return DropProposal(operation: .move)
        }
        
        updateTaskTarget(info: info)
        return DropProposal(operation: .move)
    }

    private func updateTaskTarget(info: DropInfo) {
        guard let draggedItem = DragState.shared.draggedTask else { return }
        let allTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let sorted = allTasks.filter {
            $0.intervalType == item.intervalType && $0.deletedAt == nil && !$0.completed && $0.id != draggedItem.id
        }.sorted { $0.order < $1.order }
        let rowIndex = sorted.firstIndex(where: { $0.id == item.id }) ?? sorted.count
        let bottomHalf = info.location.y > max(24, sectionFontSize * 1.2) / 2
        let proposedIndex = min(sorted.count, rowIndex + (bottomHalf && item.id != draggedItem.id ? 1 : 0))
        guard DragState.shared.targetIntervalType != item.intervalType
                || DragState.shared.targetIndex != proposedIndex else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            DragState.shared.targetIntervalType = item.intervalType
            DragState.shared.targetFontSize = sectionFontSize
            DragState.shared.targetIndex = proposedIndex
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Handle habit drop into 1 Hour at the dynamically determined index
        if let habit = HabitDragState.shared.draggedHabit {
            guard item.intervalType == HabitTaskLink.hourInterval else {
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
            insertHabitAsTask(habit: habit, at: .atIndex(targetIdx), listTitle: HabitTaskLink.hourInterval, context: context)
            withAnimation(.easeInOut(duration: 0.15)) {
                HabitDragState.shared.reset()
            }
            return true
        }
        
        guard let draggedItem = DragState.shared.draggedTask else { return false }
        let changed = TaskDragMutation.commit(
            draggedItem,
            to: item.intervalType,
            index: DragState.shared.targetIndex ?? 0,
            context: context
        )
        if changed {
            SoundManager.playTaskDropped()
            _ = PersistenceSafety.save(context)
            SupabaseSyncManager.shared.push()
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            DragState.shared.reset()
        }
        return true
    }
}
#endif

#endif
