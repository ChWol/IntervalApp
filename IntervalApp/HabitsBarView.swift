import SwiftUI
import SwiftData

struct HabitsBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \HabitItem.order) private var habits: [HabitItem]
    
    @State private var newHabitText: String = ""
    @State private var isAdding: Bool = false
    @State private var selectedFrequency: String = "Daily"
    @State private var hoveredHabitId: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RITUALS")
                    .font(.system(size: 10, weight: .light, design: .default))
                    .tracking(2.0)
                    .foregroundColor(.gray)
                
                Spacer()
                
                if !isAdding {
                    Button(action: { withAnimation { isAdding = true } }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9))
                            Text("New Ritual")
                                .font(.system(size: 10, weight: .light))
                        }
                        .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Habits Chips Container
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(habits) { habit in
                        HabitChipView(habit: habit, hoveredHabitId: $hoveredHabitId)
                    }
                    
                    if isAdding {
                        HStack(spacing: 8) {
                            Picker("", selection: $selectedFrequency) {
                                Text("Daily").tag("Daily")
                                Text("Weekly").tag("Weekly")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 110)
                            
                            TextField("Habit name...", text: $newHabitText, onCommit: createHabit)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .light))
                                .frame(width: 120)
                            
                            Button(action: createHabit) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { withAnimation { isAdding = false; newHabitText = "" } }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    
                    if habits.isEmpty && !isAdding {
                        Text("No rituals added yet. Click + New Ritual to set daily or weekly habits.")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.bottom, 20)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: colorScheme == .dark ? 0.15 : 0.9)),
            alignment: .bottom
        )
    }
    
    private func createHabit() {
        let trimmed = newHabitText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let maxOrder = (habits.map { $0.order }.max() ?? -1) + 1
            let newHabit = HabitItem(text: trimmed, frequency: selectedFrequency, order: maxOrder)
            modelContext.insert(newHabit)
            try? modelContext.save()
            newHabitText = ""
        }
        withAnimation {
            isAdding = false
        }
    }
}

struct HabitChipView: View {
    @Bindable var habit: HabitItem
    @Binding var hoveredHabitId: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDone = habit.isCompletedCurrentPeriod
        
        HStack(spacing: 8) {
            Button(action: toggleCompletion) {
                HStack(spacing: 6) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(isDone ? .primary : .secondary)
                    
                    Text(habit.text)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(isDone ? .secondary : .primary)
                        .strikethrough(isDone)
                    
                    if habit.streak > 0 {
                        Text("\(habit.streak)\(habit.frequency == "Daily" ? "d" : "w")")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(isDone ? .secondary : .primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(0.18))
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            
            if hoveredHabitId == habit.id {
                Button(action: deleteHabit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDone ? Color.gray.opacity(colorScheme == .dark ? 0.12 : 0.06) : Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.1))
        )
        .onHover { hovering in
            hoveredHabitId = hovering ? habit.id : nil
        }
    }
    
    private func toggleCompletion() {
        withAnimation(.easeInOut(duration: 0.15)) {
            if habit.isCompletedCurrentPeriod {
                habit.streak = max(0, habit.streak - 1)
                habit.lastCompletedDate = nil
            } else {
                habit.streak += 1
                habit.lastCompletedDate = Date()
            }
            try? modelContext.save()
        }
    }
    
    private func deleteHabit() {
        withAnimation {
            modelContext.delete(habit)
            try? modelContext.save()
        }
    }
}
