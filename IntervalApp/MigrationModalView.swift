#if !os(watchOS)
import SwiftUI

struct MigrationModalView: View {
    let migration: Migration
    let tasks: [TaskItem]
    let habits: [HabitItem]
    var reverseTasks: [TaskItem] = []
    let onMigrate: (Set<String>, Set<String>, Set<String>) -> Void
    let onCommitGoals: ([String]) -> Void
    let onSkip: () -> Void
    
    @State private var selectedTaskIds: Set<String> = []
    @State private var selectedHabitIds: Set<String> = []
    @State private var selectedReverseTaskIds: Set<String> = []
    @State private var yearGoals: [String] = ["", "", ""]
    @Environment(\.colorScheme) private var colorScheme
    
    private var isYearReset: Bool {
        migration.source == "1 Year" && migration.dest == "1 Year"
    }
    
    /// Only the hourly step offers habits alongside the day's tasks.
    private var isHourMigration: Bool {
        migration.source == "1 Day" && migration.dest == HabitTaskLink.hourInterval
    }
    
    private var modalTitle: String {
        switch (migration.source, migration.dest) {
        case ("1 Day", "1 Hour"):
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeString = formatter.string(from: Date())
            return String(format: "It's %@!".localized, timeString)
        case ("1 Week", "1 Day"):
            return "It's a new day – let's get it on!".localized
        case ("1 Month", "1 Week"):
            return "Fresh start into the next week – let's do some planning!".localized
        case ("1 Year", "1 Month"):
            return "Time to reflect on your yearly goals!".localized
        case ("1 Year", "1 Year"):
            return "Happy New Year!".localized
        default:
            return "Migrate Tasks".localized
        }
    }
    
    private var modalSubtitle: String {
        switch (migration.source, migration.dest) {
        case ("1 Day", "1 Hour"):
            if migration.isFirstHourOfDay {
                return "How shall we start today? Pick tasks from your 1 Day list and habits to begin.".localized
            }
            return "Want to move any of these tasks or habits into your next hour's focus?".localized
        case ("1 Week", "1 Day"):
            return "Let's plan the day! What should be your top goals based on what you planned for the week?".localized
        case ("1 Month", "1 Week"):
            return "What should be the top goals for the week based on what you planned for the month?".localized
        case ("1 Year", "1 Month"):
            return "What should this month be about? Select items from your 1 Year list to focus on this month.".localized
        case ("1 Year", "1 Year"):
            return "New year, new you? What should we plan for the year? Take some time to set your goals.".localized
        default:
            return "Would you like to transfer these tasks?".localized
        }
    }
    
    private var reverseSectionTitle: String {
        switch (migration.source, migration.dest) {
        case ("1 Day", "1 Hour"):
            return "You've been meaning to do these tasks for the past 3 hours — move to your Day overview to regain focus?".localized
        case ("1 Week", "1 Day"):
            return "These tasks have been on your Day list for 2+ days — move to your Week overview?".localized
        case ("1 Month", "1 Week"):
            return "These tasks have been on your Week list for 2+ weeks — move to your Month overview?".localized
        case ("1 Year", "1 Month"):
            return "These tasks have been on your Month list for 3+ months — move to your Year overview?".localized
        default:
            return "Move lingering tasks to overview?".localized
        }
    }
    
    private var reverseBadgeText: String? {
        guard let parent = TaskAgingHelper.parentInterval(for: migration.dest) else { return nil }
        return "→ \(parent.uppercased().localized)"
    }
    
    var body: some View {
        ZStack {
            // Darkened/greyed out backdrop for strong modal focus
            Color.black.opacity(0.75).ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 18) {
                Text(modalTitle)
                    .font(.title)
                    .fontWeight(.light)
                
                Text(modalSubtitle)
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                
                if isYearReset {
                    yearGoalsEditor
                } else if isHourMigration {
                    hourSplitPicker
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if tasks.isEmpty && reverseTasks.isEmpty {
                                emptyHint("No incomplete tasks available to transfer.".localized)
                            } else if !tasks.isEmpty {
                                ForEach(tasks) { task in
                                    selectionRow(text: task.text, isSelected: selectedTaskIds.contains(task.id)) {
                                        toggle(task.id, in: &selectedTaskIds)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: reverseTasks.isEmpty ? 250 : 180)
                }
                
                // Intelligent Reverse Demotion Section
                if !reverseTasks.isEmpty && !isYearReset {
                    reverseDemotionSection
                }
                
                let hasSelection = isYearReset
                    ? yearGoals.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    : (!selectedTaskIds.isEmpty || !selectedHabitIds.isEmpty || !selectedReverseTaskIds.isEmpty)

                HStack(spacing: 12) {
                    Spacer()
                    
                    // Skip button: Active ONLY when nothing is selected, or triggered via Escape (ESC)
                    Button("Skip".localized) { onSkip() }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .foregroundColor(hasSelection ? .secondary.opacity(0.3) : .primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(hasSelection ? 0.2 : 0.6), lineWidth: 1)
                        )
                        .disabled(hasSelection)
                        .pointingHandCursor()
                        .keyboardShortcut(.cancelAction)
                        .keyboardShortcut(.escape, modifiers: [])
                    
                    if isYearReset {
                        Button("Commit".localized) {
                            let validGoals = yearGoals.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            onCommitGoals(validGoals)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(hasSelection ? Color.primary : Color.primary.opacity(0.12))
                        .foregroundColor(hasSelection ? Color(colorScheme == .dark ? .black : .white) : Color.secondary.opacity(0.4))
                        .cornerRadius(8)
                        .disabled(!hasSelection)
                        .pointingHandCursor()
                        .keyboardShortcut(.defaultAction)
                    } else {
                        // Migrate button: Active ONLY when at least one item is selected
                        Button("Migrate".localized) {
                            onMigrate(selectedTaskIds, selectedHabitIds, selectedReverseTaskIds)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(hasSelection ? Color.primary : Color.primary.opacity(0.12))
                        .foregroundColor(hasSelection ? Color(colorScheme == .dark ? .black : .white) : Color.secondary.opacity(0.4))
                        .cornerRadius(8)
                        .disabled(!hasSelection)
                        .pointingHandCursor()
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.top, 6)
            }
            .padding(36)
            .background(Color(colorScheme == .dark ? .black : .white))
            .cornerRadius(16)
            .shadow(radius: 20)
            .frame(maxWidth: isHourMigration ? 620 : 520)
            .padding(20)
        }
        #if os(macOS)
        .onExitCommand {
            onSkip()
        }
        #endif
        .onAppear {
            selectedTaskIds = []
            selectedHabitIds = []
            selectedReverseTaskIds = []
        }
    }
    
    // MARK: - Reverse Demotion Section
    
    private var reverseDemotionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(Color(white: colorScheme == .dark ? 0.22 : 0.88))
                .padding(.vertical, 2)
            
            Text(reverseSectionTitle)
                .font(.system(size: 12, weight: .light))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(reverseTasks) { task in
                        selectionRow(
                            text: task.text,
                            isSelected: selectedReverseTaskIds.contains(task.id),
                            badge: reverseBadgeText
                        ) {
                            toggle(task.id, in: &selectedReverseTaskIds)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
    }
    
    // MARK: - Hour Migration: Tasks beside Habits
    
    private var hourSplitPicker: some View {
        HStack(alignment: .top, spacing: 0) {
            pickerColumn(title: "FROM YOUR DAY".localized) {
                if tasks.isEmpty {
                    emptyHint("Nothing left in your 1 Day list.".localized)
                } else {
                    ForEach(tasks) { task in
                        selectionRow(text: task.text, isSelected: selectedTaskIds.contains(task.id)) {
                            toggle(task.id, in: &selectedTaskIds)
                        }
                    }
                }
            }
            
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(white: colorScheme == .dark ? 0.18 : 0.9))
                .padding(.horizontal, 18)
            
            pickerColumn(title: "HABITS".localized) {
                if habits.isEmpty {
                    emptyHint("No habits left for this period.".localized)
                } else {
                    ForEach(habits) { habit in
                        selectionRow(
                            text: habit.text,
                            isSelected: selectedHabitIds.contains(habit.id),
                            badge: nil
                        ) {
                            toggle(habit.id, in: &selectedHabitIds)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: reverseTasks.isEmpty ? 250 : 180)
    }
    
    private func pickerColumn<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .light))
                .tracking(2.0)
                .foregroundColor(.gray)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Shared Pieces
    
    private func selectionRow(text: String, isSelected: Bool, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .primary : .secondary)
                Text(text)
                    .fontWeight(.light)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.gray.opacity(0.18)))
                }
                
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func emptyHint(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .light))
            .foregroundColor(.secondary)
            .padding(.vertical, 10)
    }
    
    private var yearGoalsEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<yearGoals.count, id: \.self) { idx in
                    HStack(spacing: 12) {
                        Text("–")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.secondary)
                        TextField(String(format: "Goal #%d...".localized, idx + 1), text: $yearGoals[idx])
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .light))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
                    )
                }
                
                Button(action: { yearGoals.append("") }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add Another Goal".localized)
                    }
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxHeight: 250)
    }
    
    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }
}
#endif
