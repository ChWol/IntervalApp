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
    @FocusState private var isInputFocused: Bool
    
    private var hourTasks: [TaskItem] {
        allTasks.filter { $0.intervalType == "1 Hour" && $0.deletedAt == nil && !$0.completed }
            .sorted { $0.order < $1.order }
    }
    
    private var completedHourTasks: [TaskItem] {
        allTasks.filter { $0.intervalType == "1 Hour" && $0.deletedAt == nil && $0.completed }
            .sorted { ($0.completedAt ?? Date()) > ($1.completedAt ?? Date()) }
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
            // MARK: - Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("1 HOUR FOCUS".localized)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2.0)
                        .foregroundColor(.secondary)
                    
                    Text(currentHourRangeString)
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                HourProgressView(showRing: true, fontSize: 11)
            }
            .padding(.bottom, 4)
            
            Divider()
                .opacity(0.4)
            
            // MARK: - Tasks List
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
                
                // Completed Tasks Section
                if !completedHourTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\("COMPLETED".localized) (\(completedHourTasks.count))")
                            .font(.system(size: 9, weight: .light))
                            .tracking(1.5)
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 4)
                        
                        ForEach(completedHourTasks.prefix(3)) { task in
                            HStack(spacing: 8) {
                                Button(action: {
                                    toggleTask(task)
                                }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                
                                Text(task.text)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                                    .strikethrough(true)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            
            // MARK: - Quick Add Input
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
                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.08))
            )
            
            Divider()
                .opacity(0.4)
            
            // MARK: - Footer Actions
            HStack {
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
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit".localized)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
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
