import SwiftUI
import SwiftData
#if os(watchOS)
import WatchKit
#endif

// MARK: - Watch Task List View

public struct WatchTaskListView: View {
    @Environment(\.modelContext) private var modelContext
    let intervalType: String
    let headerTitle: String
    let remainingText: String

    @Query private var allTasks: [TaskItem]
    @Query private var allHabits: [HabitItem]

    public init(intervalType: String, headerTitle: String, remainingText: String) {
        self.intervalType = intervalType
        self.headerTitle = headerTitle
        self.remainingText = remainingText
        
        let targetInterval = intervalType
        _allTasks = Query(
            filter: #Predicate<TaskItem> { item in
                item.intervalType == targetInterval && item.deletedAt == nil
            },
            sort: \TaskItem.order,
            animation: .easeInOut(duration: 0.15)
        )
    }

    private var activeTasks: [TaskItem] {
        allTasks.filter { !$0.completed }
    }

    private var completedTasks: [TaskItem] {
        allTasks.filter { $0.completed }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                // Header: Interval Title & Countdown
                HStack {
                    Text(headerTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(remainingText)
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

                if allTasks.isEmpty {
                    VStack(spacing: 4) {
                        Spacer(minLength: 12)
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Keine Aufgaben".localized)
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    // Active Tasks
                    ForEach(activeTasks) { task in
                        WatchTaskRow(task: task, allHabits: allHabits)
                    }

                    // Completed Tasks (Dimmed, below)
                    if !completedTasks.isEmpty {
                        Divider()
                            .overlay(Color.white.opacity(0.1))
                            .padding(.vertical, 4)

                        ForEach(completedTasks) { task in
                            WatchTaskRow(task: task, allHabits: allHabits)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Watch Task Row

public struct WatchTaskRow: View {
    @Environment(\.modelContext) private var modelContext
    var task: TaskItem
    var allHabits: [HabitItem]

    public var body: some View {
        Button {
            toggleTask()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(task.completed ? .secondary.opacity(0.5) : .primary)

                Text(task.text.isEmpty ? "Aufgabe".localized : task.text)
                    .font(.system(size: 13, weight: .light))
                    .strikethrough(task.completed, color: .secondary)
                    .foregroundColor(task.completed ? .secondary.opacity(0.5) : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(task.completed ? 0.03 : 0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleTask() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(task.completed ? .click : .success)
        #endif

        let targetCompleted = !task.completed
        withAnimation(.easeInOut(duration: 0.15)) {
            HabitTaskLink.setTaskCompleted(targetCompleted, on: task)
            if task.intervalType == HabitTaskLink.hourInterval {
                HabitTaskLink.applyTaskCompletionToHabit(task, habits: allHabits)
            }
            
            if targetCompleted {
                SoundManager.playTaskCompleted()
            } else {
                SoundManager.playUndo()
            }
        }

        try? modelContext.save()
        SupabaseSyncManager.shared.push()
    }
}

// MARK: - Watch Habits List View

public struct WatchHabitsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<HabitItem> { item in
            item.deletedAt == nil
        },
        sort: \HabitItem.order,
        animation: .easeInOut(duration: 0.15)
    ) private var habits: [HabitItem]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack {
                    Text("GEWOHNHEITEN".localized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    let completedCount = habits.filter { $0.isCompletedCurrentPeriod }.count
                    Text("\(completedCount)/\(habits.count)")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

                if habits.isEmpty {
                    VStack(spacing: 4) {
                        Spacer(minLength: 12)
                        Image(systemName: "flame")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Keine Gewohnheiten".localized)
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    ForEach(habits) { habit in
                        WatchHabitRow(habit: habit)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Watch Habit Row

public struct WatchHabitRow: View {
    @Environment(\.modelContext) private var modelContext
    var habit: HabitItem

    public var body: some View {
        Button {
            toggleHabit()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: habit.isCompletedCurrentPeriod ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(habit.isCompletedCurrentPeriod ? .green.opacity(0.8) : .primary)

                Text(habit.text)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(habit.isCompletedCurrentPeriod ? .secondary.opacity(0.6) : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if habit.streak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange.opacity(0.8))
                        Text("\(habit.streak)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(habit.isCompletedCurrentPeriod ? 0.03 : 0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleHabit() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(habit.isCompletedCurrentPeriod ? .click : .success)
        #endif

        let targetCompleted = !habit.isCompletedCurrentPeriod
        withAnimation(.easeInOut(duration: 0.15)) {
            HabitTaskLink.setHabitCompleted(targetCompleted, on: habit)
            
            if targetCompleted {
                SoundManager.playHabitCompleted()
            } else {
                SoundManager.playUndo()
            }
        }

        try? modelContext.save()
        SupabaseSyncManager.shared.push()
    }
}
