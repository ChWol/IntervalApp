import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine

struct HabitsBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \HabitItem.order) private var habits: [HabitItem]
    
    @State private var newHabitText: String = ""
    @State private var isAdding: Bool = false
    @State private var selectedFrequency: String = "Daily"
    @State private var hoveredHabitId: String? = nil
    @FocusState private var isInputFocused: Bool
    
    private var sortedHabits: [HabitItem] {
        let incomplete = habits.filter { !$0.isCompletedCurrentPeriod }.sorted { $0.order < $1.order }
        let completed = habits.filter { $0.isCompletedCurrentPeriod }.sorted { $0.order < $1.order }
        return incomplete + completed
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HABITS")
                .font(.system(size: 10, weight: .light, design: .default))
                .tracking(2.0)
                .foregroundColor(.gray)
            
            // Habits Chips Container
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sortedHabits) { habit in
                        HabitChipView(habit: habit, hoveredHabitId: $hoveredHabitId)
                            .onDrag {
                                HabitDragState.shared.draggedHabit = habit
                                return NSItemProvider(object: habit.id as NSString)
                            }
                            .onDrop(of: [.data], delegate: HabitDropDelegate(item: habit, context: modelContext))
                    }
                    
                    if !isAdding {
                        Button(action: {
                            withAnimation {
                                isAdding = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                isInputFocused = true
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(colorScheme == .dark ? 0.12 : 0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 8) {
                            // Minimalist Daily | Weekly Toggle
                            HStack(spacing: 6) {
                                Button("daily") {
                                    withAnimation { selectedFrequency = "Daily" }
                                }
                                .foregroundColor(selectedFrequency == "Daily" ? .primary : .secondary)
                                .font(.system(size: 10, weight: selectedFrequency == "Daily" ? .medium : .light))
                                .buttonStyle(.plain)
                                
                                Text("|")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray.opacity(0.4))
                                
                                Button("weekly") {
                                    withAnimation { selectedFrequency = "Weekly" }
                                }
                                .foregroundColor(selectedFrequency == "Weekly" ? .primary : .secondary)
                                .font(.system(size: 10, weight: selectedFrequency == "Weekly" ? .medium : .light))
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.18 : 0.1))
                            )
                            
                            TextField("Habit name...", text: $newHabitText, onCommit: createHabit)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .light))
                                .frame(width: 120)
                                .focused($isInputFocused)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        isInputFocused = true
                                    }
                                }
                            
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
                        #if os(macOS)
                        .onExitCommand {
                            withAnimation {
                                isAdding = false
                                newHabitText = ""
                            }
                        }
                        #endif
                    }
                    
                    if habits.isEmpty && !isAdding {
                        Text("No habits added yet. Click + New Habit to set daily or weekly routines.")
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
            SupabaseSyncManager.shared.push()
            newHabitText = ""
        }
        withAnimation {
            isAdding = false
        }
    }
}

// MARK: - Habit Chip Component

struct HabitChipView: View {
    @Bindable var habit: HabitItem
    @Binding var hoveredHabitId: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var dragState = HabitDragState.shared
    
    private var isDragged: Bool {
        dragState.draggedHabit?.id == habit.id
    }
    
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
                    
                    // Streak badge is only displayed when NOT completed
                    if habit.streak > 0 && !isDone {
                        Text("\(habit.streak)\(habit.frequency == "Daily" ? "d" : "w")")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
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
        .opacity(isDragged ? 0.3 : 1.0)
        .onHover { hovering in
            hoveredHabitId = hovering ? habit.id : nil
        }
    }
    
    private func toggleCompletion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if habit.isCompletedCurrentPeriod {
                habit.streak = max(0, habit.streak - 1)
                habit.lastCompletedDate = nil
            } else {
                habit.streak += 1
                habit.lastCompletedDate = Date()
            }
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
    
    private func deleteHabit() {
        withAnimation {
            modelContext.delete(habit)
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
}

// MARK: - Habit Drag & Drop Reordering

class HabitDragState: ObservableObject {
    static let shared = HabitDragState()
    @Published var draggedHabit: HabitItem?
}

struct HabitDropDelegate: DropDelegate {
    let item: HabitItem
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let draggedItem = HabitDragState.shared.draggedHabit else { return }
        if draggedItem.id != item.id {
            withAnimation(.easeInOut(duration: 0.2)) {
                let descriptor = FetchDescriptor<HabitItem>()
                guard let allHabits = try? context.fetch(descriptor) else { return }
                var sorted = allHabits.sorted { $0.order < $1.order }
                
                if let sourceIdx = sorted.firstIndex(where: { $0.id == draggedItem.id }),
                   let targetIdx = sorted.firstIndex(where: { $0.id == item.id }) {
                    let moved = sorted.remove(at: sourceIdx)
                    sorted.insert(moved, at: targetIdx)
                }
                
                for (i, h) in sorted.enumerated() {
                    h.order = i
                }
                try? context.save()
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.easeInOut(duration: 0.15)) {
            HabitDragState.shared.draggedHabit = nil
        }
        return true
    }
}
