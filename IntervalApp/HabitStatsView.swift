#if !os(watchOS)
import SwiftUI
import SwiftData

struct HabitStatsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \HabitItem.order) private var habits: [HabitItem]
    @State private var selectedHabitId: String?

    private let calendar = Calendar.current
    private var year: Int { calendar.component(.year, from: Date()) }

    private var activeHabits: [HabitItem] {
        habits.filter { $0.deletedAt == nil }.sorted { $0.order < $1.order }
    }

    private var selectedHabit: HabitItem? {
        activeHabits.first(where: { $0.id == selectedHabitId }) ?? activeHabits.first
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HABIT RHYTHMS".localized)
                        .font(.system(size: 10, weight: .light))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    Text("A quiet look back at what you kept showing up for.".localized)
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(.secondary)
                }

                if activeHabits.isEmpty {
                    Text("No active habits yet.".localized)
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 36)
                } else {
                    habitPicker
                    if let habit = selectedHabit {
                        summary(for: habit)
                        yearCalendar(for: habit)
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if selectedHabitId == nil { selectedHabitId = activeHabits.first?.id }
        }
        .onChange(of: activeHabits.map(\.id)) { _, ids in
            if let selectedHabitId, ids.contains(selectedHabitId) == false {
                self.selectedHabitId = ids.first
            }
        }
    }

    private var habitPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeHabits) { habit in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedHabitId = habit.id }
                    } label: {
                        Text(habit.text)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .foregroundStyle(selectedHabit?.id == habit.id ? (colorScheme == .dark ? .black : .white) : .primary)
                            .background(
                                Capsule().fill(selectedHabit?.id == habit.id ? Color.primary : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func summary(for habit: HabitItem) -> some View {
        HStack(spacing: 0) {
            stat(value: "\(habit.streak)", label: "CURRENT STREAK".localized)
            Divider().frame(height: 34).opacity(0.35)
            stat(value: "\(completionsThisYear(for: habit))", label: "THIS YEAR".localized)
            Divider().frame(height: 34).opacity(0.35)
            stat(value: rhythmDescription(for: habit), label: "RHYTHM".localized)
        }
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
        )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 22, weight: .light, design: .rounded)).lineLimit(1)
            Text(label).font(.system(size: 8, weight: .light)).tracking(1.1).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func yearCalendar(for habit: HabitItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(verbatim: yearHeader).font(.system(size: 10, weight: .light)).tracking(1.8).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Color.primary.opacity(0.12)).frame(width: 8, height: 8)
                    Text("complete".localized).font(.system(size: 9, weight: .light)).foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18)], spacing: 20) {
                ForEach(1...12, id: \.self) { month in monthView(month: month, dates: completionDates(for: habit)) }
            }
        }
    }

    private func monthView(month: Int, dates: [Date]) -> some View {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let leading = calendar.component(.weekday, from: first) - 1

        return VStack(alignment: .leading, spacing: 7) {
            Text(calendar.monthSymbols[month - 1].uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4) {
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 13) }
                ForEach(1...dayCount, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: first) ?? first
                    let completed = dates.contains {
                        calendar.isDate(HabitItem.intervalDayDate(for: $0), inSameDayAs: HabitItem.intervalDayDate(for: date))
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(completed ? Color.primary.opacity(0.76) : Color.primary.opacity(0.07))
                        .frame(height: 13)
                        .accessibilityLabel(completed ? "Completed \(date.formatted(date: .abbreviated, time: .omitted))" : date.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    private func completionsThisYear(for habit: HabitItem) -> Int {
        completionDates(for: habit).filter {
            calendar.component(.year, from: HabitItem.intervalDayDate(for: $0)) == year
        }.count
    }

    private var yearHeader: String { String(year) + " " + "RHYTHM".localized }

    private func completionDates(for habit: HabitItem) -> [Date] {
        var dates = habit.completionDates
        // Older stores only had lastCompletedDate. Include it so existing
        // habits immediately show a meaningful count after upgrading.
        if let legacy = habit.lastCompletedDate,
           !dates.contains(where: { calendar.isDate(HabitItem.intervalDayDate(for: $0), inSameDayAs: HabitItem.intervalDayDate(for: legacy)) }) {
            dates.append(legacy)
        }
        return dates
    }

    private func rhythmDescription(for habit: HabitItem) -> String {
        guard habit.isWeekly else { return "Daily".localized }
        guard let weekday = habit.targetWeekday,
              weekday >= 1, weekday <= calendar.weekdaySymbols.count else {
            return "Weekly".localized
        }
        return "Weekly · \(calendar.weekdaySymbols[weekday - 1].localized)"
    }
}
#endif
