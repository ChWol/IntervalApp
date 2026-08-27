import SwiftUI
import SwiftData

#if os(macOS)
import AppKit

struct MenuBarTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var locManager = LocalizationManager.shared
    
    @Query(sort: \TaskItem.order) private var allTasks: [TaskItem]
    
    @State private var newTaskText: String = ""
    @State private var isInputHovered: Bool = false
    @FocusState private var isInputFocused: Bool
    
    private var hourTasks: [TaskItem] {
        allTasks.filter { $0.intervalType == "1 Hour" && $0.deletedAt == nil && !$0.completed }
            .sorted { $0.order < $1.order }
    }
    
    private var currentHourRangeString: String {
        let calendar = Calendar.current
        let now = Date()
        let startHour = calendar.component(.hour, from: now)
        let nextHour = (startHour + 1) % 24
        return String(format: "%02d:00 – %02d:00", startHour, nextHour)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - Header with Timeline Progress
            VStack(alignment: .leading, spacing: 6) {
                Text("1 HOUR FOCUS".localized)
                    .font(.system(size: 10, weight: .light))
                    .tracking(2.0)
                    .foregroundColor(.secondary)
                
                HourProgressView()
            }
            .padding(.bottom, 2)
            
            Divider()
                .opacity(0.4)
            
            // MARK: - Tasks List (active only, no completed)
            VStack(alignment: .leading, spacing: 8) {
                if hourTasks.isEmpty {
                    Text("No tasks in 1 Hour focus.".localized)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.vertical, 8)
                } else {
                    ForEach(hourTasks) { task in
                        HStack(spacing: 8) {
                            Button(action: {
                                toggleTask(task)
                            }) {
                                Image(systemName: "circle")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            
                            Text(task.text)
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 220)
            
            // MARK: - Quick Add Input (no autofocus, on-hover accent)
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(.secondary)
                
                TextField("Add 1-hour task...".localized, text: $newTaskText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .light))
                    .focused($isInputFocused)
                    .onSubmit {
                        createQuickTask()
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isInputHovered || isInputFocused
                          ? Color.gray.opacity(colorScheme == .dark ? 0.25 : 0.14)
                          : Color.gray.opacity(colorScheme == .dark ? 0.12 : 0.06))
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isInputHovered = hovering
                }
            }
            .onTapGesture {
                isInputFocused = true
            }
            
            Divider()
                .opacity(0.4)
            
            // MARK: - Footer (Open Interval only, no Quit)
            HStack {
                Spacer()
                
                Button(action: openMainWindow) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10))
                        Text("Open Interval".localized)
                            .font(.system(size: 11, weight: .light))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(Color(colorScheme == .dark ? .black : .white))
    }
    
    private func toggleTask(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            task.completed.toggle()
            if task.completed {
                task.completedAt = Date()
                SoundManager.playTaskCompleted()
            } else {
                task.completedAt = nil
                SoundManager.playUndo()
            }
            task.updatedAt = Date()
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
    
    private func createQuickTask() {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        let descriptor = FetchDescriptor<TaskItem>()
        if let all = try? modelContext.fetch(descriptor) {
            let sorted = all.filter { $0.intervalType == "1 Hour" && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
            let maxOrder = (sorted.last?.order ?? -1) + 1
            let newTask = TaskItem(text: trimmed, intervalType: "1 Hour", order: maxOrder)
            modelContext.insert(newTask)
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
            newTaskText = ""
        }
    }
    
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
#endif
