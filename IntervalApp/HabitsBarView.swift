import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine
#if os(macOS)
import AppKit
#endif

// MARK: - Weekday Option Helper

struct WeekdayOption: Identifiable {
    let id: Int // 1 = Sun, 2 = Mon, 3 = Tue, 4 = Wed, 5 = Thu, 6 = Fri, 7 = Sat (Calendar.component(.weekday))
    let shortNameEn: String
    let shortNameDe: String
    let shortNameFr: String
    let shortNameEs: String
    let shortNamePt: String
    let shortNameIt: String
    let shortNameAr: String
    let shortNameZh: String
    let shortNameJa: String
    let shortNameKo: String
    let fullNameEn: String
    let fullNameDe: String
    let fullNameFr: String
    let fullNameEs: String
    let fullNamePt: String
    let fullNameIt: String
    let fullNameAr: String
    let fullNameZh: String
    let fullNameJa: String
    let fullNameKo: String
    
    var shortName: String {
        switch LocalizationManager.shared.currentLanguage {
        case .german: return shortNameDe
        case .french: return shortNameFr
        case .spanish: return shortNameEs
        case .portuguese: return shortNamePt
        case .italian: return shortNameIt
        case .arabic: return shortNameAr
        case .chinese: return shortNameZh
        case .japanese: return shortNameJa
        case .korean: return shortNameKo
        case .english: return shortNameEn
        }
    }
    
    var fullName: String {
        switch LocalizationManager.shared.currentLanguage {
        case .german: return fullNameDe
        case .french: return fullNameFr
        case .spanish: return fullNameEs
        case .portuguese: return fullNamePt
        case .italian: return fullNameIt
        case .arabic: return fullNameAr
        case .chinese: return fullNameZh
        case .japanese: return fullNameJa
        case .korean: return fullNameKo
        case .english: return fullNameEn
        }
    }
    
    static let allMondayFirst: [WeekdayOption] = [
        WeekdayOption(id: 2, shortNameEn: "Mon", shortNameDe: "Mo", shortNameFr: "Lun", shortNameEs: "Lun", shortNamePt: "Seg", shortNameIt: "Lun", shortNameAr: "إث", shortNameZh: "周一", shortNameJa: "月", shortNameKo: "월", fullNameEn: "Monday", fullNameDe: "Montag", fullNameFr: "Lundi", fullNameEs: "Lunes", fullNamePt: "Segunda-feira", fullNameIt: "Lunedì", fullNameAr: "الإثنين", fullNameZh: "星期一", fullNameJa: "月曜日", fullNameKo: "월요일"),
        WeekdayOption(id: 3, shortNameEn: "Tue", shortNameDe: "Di", shortNameFr: "Mar", shortNameEs: "Mar", shortNamePt: "Ter", shortNameIt: "Mar", shortNameAr: "ثل", shortNameZh: "周二", shortNameJa: "火", shortNameKo: "화", fullNameEn: "Tuesday", fullNameDe: "Dienstag", fullNameFr: "Mardi", fullNameEs: "Martes", fullNamePt: "Terça-feira", fullNameIt: "Martedì", fullNameAr: "الثلاثاء", fullNameZh: "星期二", fullNameJa: "火曜日", fullNameKo: "화요일"),
        WeekdayOption(id: 4, shortNameEn: "Wed", shortNameDe: "Mi", shortNameFr: "Mer", shortNameEs: "Mié", shortNamePt: "Qua", shortNameIt: "Mer", shortNameAr: "أر", shortNameZh: "周三", shortNameJa: "水", shortNameKo: "수", fullNameEn: "Wednesday", fullNameDe: "Mittwoch", fullNameFr: "Mercredi", fullNameEs: "Miércoles", fullNamePt: "Quarta-feira", fullNameIt: "Mercoledì", fullNameAr: "الأربعاء", fullNameZh: "星期三", fullNameJa: "水曜日", fullNameKo: "수요일"),
        WeekdayOption(id: 5, shortNameEn: "Thu", shortNameDe: "Do", shortNameFr: "Jeu", shortNameEs: "Jue", shortNamePt: "Qui", shortNameIt: "Gio", shortNameAr: "خم", shortNameZh: "周四", shortNameJa: "木", shortNameKo: "목", fullNameEn: "Thursday", fullNameDe: "Donnerstag", fullNameFr: "Jeudi", fullNameEs: "Jueves", fullNamePt: "Quinta-feira", fullNameIt: "Giovedì", fullNameAr: "الخميس", fullNameZh: "星期四", fullNameJa: "木曜日", fullNameKo: "목요일"),
        WeekdayOption(id: 6, shortNameEn: "Fri", shortNameDe: "Fr", shortNameFr: "Ven", shortNameEs: "Vie", shortNamePt: "Sex", shortNameIt: "Ven", shortNameAr: "جم", shortNameZh: "周五", shortNameJa: "金", shortNameKo: "금", fullNameEn: "Friday", fullNameDe: "Freitag", fullNameFr: "Vendredi", fullNameEs: "Viernes", fullNamePt: "Sexta-feira", fullNameIt: "Venerdì", fullNameAr: "الجمعة", fullNameZh: "星期五", fullNameJa: "金曜日", fullNameKo: "금요일"),
        WeekdayOption(id: 7, shortNameEn: "Sat", shortNameDe: "Sa", shortNameFr: "Sam", shortNameEs: "Sáb", shortNamePt: "Sáb", shortNameIt: "Sab", shortNameAr: "سب", shortNameZh: "周六", shortNameJa: "土", shortNameKo: "토", fullNameEn: "Saturday", fullNameDe: "Samstag", fullNameFr: "Samedi", fullNameEs: "Sábado", fullNamePt: "Sábado", fullNameIt: "Sabato", fullNameAr: "السبت", fullNameZh: "星期六", fullNameJa: "土曜日", fullNameKo: "토요일"),
        WeekdayOption(id: 1, shortNameEn: "Sun", shortNameDe: "So", shortNameFr: "Dim", shortNameEs: "Dom", shortNamePt: "Dom", shortNameIt: "Dom", shortNameAr: "أح", shortNameZh: "周日", shortNameJa: "日", shortNameKo: "일", fullNameEn: "Sunday", fullNameDe: "Sonntag", fullNameFr: "Dimanche", fullNameEs: "Domingo", fullNamePt: "Domingo", fullNameIt: "Domenica", fullNameAr: "الأحد", fullNameZh: "星期日", fullNameJa: "日曜日", fullNameKo: "일요일")
    ]
    
    static var allCurrentOrder: [WeekdayOption] {
        let start = UserDefaults.standard.string(forKey: "weekStartDay") ?? "Monday"
        if start == "Sunday" {
            let sunday = allMondayFirst.filter { $0.id == 1 }
            let others = allMondayFirst.filter { $0.id != 1 }
            return sunday + others
        }
        return allMondayFirst
    }
    
    static func option(for id: Int) -> WeekdayOption? {
        allMondayFirst.first(where: { $0.id == id })
    }
}

// MARK: - Habits Bar View

struct HabitsBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \HabitItem.order) private var habits: [HabitItem]
    @ObservedObject private var locManager = LocalizationManager.shared
    
    @State private var newHabitText: String = ""
    @State private var isAdding: Bool = false
    @State private var selectedFrequency: String = "Daily"
    @State private var selectedWeekday: Int? = nil
    @State private var showWeekdayPopover: Bool = false
    @State private var hoveredHabitId: String? = nil
    @State private var isPlusHovered: Bool = false
    @FocusState private var isInputFocused: Bool
    #if os(macOS)
    @State private var escMonitor: Any? = nil
    #endif
    
    private var sortedHabits: [HabitItem] {
        let active = habits.filter { $0.deletedAt == nil && $0.isScheduledForTodayOrOverdue() }
        let overdueIncomplete = active.filter { $0.isOverdue() && !$0.isCompletedCurrentPeriod && !$0.isPostponedToday }
            .sorted { $0.order < $1.order }
        let todayIncomplete = active.filter { !$0.isOverdue() && !$0.isCompletedCurrentPeriod && !$0.isPostponedToday }
            .sorted { $0.order < $1.order }
        let postponed = active.filter { $0.isPostponedToday && !$0.isCompletedCurrentPeriod }
            .sorted { $0.order < $1.order }
        let completed = active.filter { $0.isCompletedCurrentPeriod }.sorted {
            ($0.lastCompletedDate ?? Date.distantPast) > ($1.lastCompletedDate ?? Date.distantPast)
        }
        return overdueIncomplete + todayIncomplete + postponed + completed
    }
    
    private var weeklyButtonLabel: String {
        if let day = selectedWeekday, let opt = WeekdayOption.option(for: day) {
            return "weekly (\(opt.shortName))"
        }
        return "weekly"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HABITS".localized)
                .font(.system(size: 10, weight: .light, design: .default))
                .tracking(2.0)
                .foregroundColor(.gray)
            
            // Habits Chips Container
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sortedHabits) { habit in
                            HabitChipView(habit: habit, hoveredHabitId: $hoveredHabitId)
                                .id(habit.id)
                                .onDrag {
                                    HabitDragState.shared.draggedHabit = habit
                                    return NSItemProvider(item: habit.id as NSString, typeIdentifier: UTType.data.identifier)
                                } preview: {
                                    Text(habit.text)
                                        .font(.system(size: 12, weight: .light))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white)
                                                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                                        )
                                }
                                .onDrop(of: [UTType.data, UTType.plainText, UTType.text], delegate: HabitDropDelegate(item: habit, context: modelContext, proxy: proxy))
                        }
                    
                    if !isAdding {
                        Button(action: {
                            withAnimation {
                                isAdding = true
                                selectedFrequency = "Daily"
                                selectedWeekday = nil
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                isInputFocused = true
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(isPlusHovered ? .primary : .secondary.opacity(0.5))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.12)) {
                                isPlusHovered = hovering
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            // Minimalist Daily | Weekly Toggle
                            HStack(spacing: 6) {
                                Button("daily") {
                                    withAnimation {
                                        selectedFrequency = "Daily"
                                        selectedWeekday = nil
                                        showWeekdayPopover = false
                                    }
                                }
                                .foregroundColor(selectedFrequency == "Daily" ? .primary : .secondary)
                                .font(.system(size: 10, weight: selectedFrequency == "Daily" ? .medium : .light))
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                
                                Text("|")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray.opacity(0.4))
                                
                                Button(action: {
                                    if selectedWeekday == nil {
                                        let currentDay = Calendar.current.component(.weekday, from: Date())
                                        selectedWeekday = currentDay
                                        selectedFrequency = "Weekly:\(currentDay)"
                                    }
                                    showWeekdayPopover = true
                                }) {
                                    Text(weeklyButtonLabel)
                                        .foregroundColor(selectedFrequency.starts(with: "Weekly") ? .primary : .secondary)
                                        .font(.system(size: 10, weight: selectedFrequency.starts(with: "Weekly") ? .medium : .light))
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                .popover(isPresented: $showWeekdayPopover, arrowEdge: .bottom) {
                                    weekdayPickerPopover
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.18 : 0.1))
                            )
                            
                            TextField("Habit name...", text: $newHabitText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .light))
                                .frame(width: 120)
                                .focused($isInputFocused)
                                .onSubmit { createHabit() }
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
                            .pointingHandCursor()
                            
                            Button(action: {
                                withAnimation {
                                    isAdding = false
                                    newHabitText = ""
                                    showWeekdayPopover = false
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
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
                                showWeekdayPopover = false
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
        }
        .padding(.bottom, 20)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: colorScheme == .dark ? 0.15 : 0.9)),
            alignment: .bottom
        )
        .onChange(of: showWeekdayPopover) { _, isShowing in
            #if os(macOS)
            if isShowing {
                escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 53 { // ESC
                        showWeekdayPopover = false
                        return nil
                    }
                    return event
                }
            } else {
                if let monitor = escMonitor {
                    NSEvent.removeMonitor(monitor)
                    escMonitor = nil
                }
            }
            #endif
        }
        .onDisappear {
            #if os(macOS)
            if let monitor = escMonitor {
                NSEvent.removeMonitor(monitor)
                escMonitor = nil
            }
            #endif
        }
    }
    
    // MARK: - Weekday Picker Popover Content
    
    @ViewBuilder
    private var weekdayPickerPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SELECT DAY OF WEEK".localized)
                .font(.system(size: 9, weight: .light))
                .tracking(1.5)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            VStack(spacing: 1) {
                ForEach(WeekdayOption.allCurrentOrder) { opt in
                    Button(action: {
                        selectedWeekday = opt.id
                        selectedFrequency = "Weekly:\(opt.id)"
                        showWeekdayPopover = false
                    }) {
                        HStack {
                            Text(opt.fullName)
                                .font(.system(size: 12, weight: selectedWeekday == opt.id ? .medium : .light))
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedWeekday == opt.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedWeekday == opt.id ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .frame(minWidth: 150)
        #if os(macOS)
        .onExitCommand { showWeekdayPopover = false }
        #endif
        .background(
            Button("") { showWeekdayPopover = false }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        )
    }
    
    private func createHabit() {
        let trimmed = newHabitText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            withAnimation { isAdding = false }
            return
        }
        newHabitText = ""
        let maxOrder = (habits.map { $0.order }.max() ?? -1) + 1
        let newHabit = HabitItem(text: trimmed, frequency: selectedFrequency, order: maxOrder)
        modelContext.insert(newHabit)
        try? modelContext.save()
        SupabaseSyncManager.shared.push()
        withAnimation {
            isAdding = false
            showWeekdayPopover = false
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
        let isPostponed = habit.isPostponedToday && !isDone
        let isOverdue = habit.isOverdue() && !isDone && !isPostponed
        
        HStack(spacing: 8) {
            Button(action: toggleCompletion) {
                HStack(spacing: 6) {
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(.primary)
                    } else if isPostponed {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(.secondary.opacity(0.8))
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(isOverdue ? .primary : .secondary)
                    }
                    
                    Text(habit.text)
                        .font(.system(size: 12, weight: isOverdue ? .medium : .light))
                        .foregroundColor(isDone || isPostponed ? .secondary : .primary)
                        .strikethrough(isDone || isPostponed)
                    
                    if habit.isWeekly, let day = habit.targetWeekday, let opt = WeekdayOption.option(for: day) {
                        Text(opt.shortName)
                            .font(.system(size: 9, weight: isOverdue ? .medium : .light))
                            .foregroundColor(isOverdue ? .primary : .secondary.opacity(0.8))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.primary.opacity(isOverdue ? (colorScheme == .dark ? 0.22 : 0.12) : 0.06))
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            
            if hoveredHabitId == habit.id {
                HStack(spacing: 6) {
                    // Postpone / Snooze for today
                    if !isDone {
                        Button(action: togglePostpone) {
                            Image(systemName: isPostponed ? "arrow.uturn.backward" : "clock")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .help(isPostponed ? "Unpostpone for today".localized : "Postpone for today".localized)
                    }
                    
                    // Delete
                    Button(action: deleteHabit) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill((isDone || isPostponed) ? Color.gray.opacity(colorScheme == .dark ? 0.12 : 0.06) : Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.1))
        )
        .onHover { hovering in
            hoveredHabitId = hovering ? habit.id : nil
        }
    }
    
    private func togglePostpone() {
        withAnimation(.easeInOut(duration: 0.2)) {
            habit.togglePostponeForToday()
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
    
    private func toggleCompletion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            let now = Date()
            let willBeCompleted = !habit.isCompletedCurrentPeriod
            if willBeCompleted {
                SoundManager.playHabitCompleted()
                // If it was postponed, un-postpone it when completed
                if habit.isPostponedToday {
                    habit.postponedDate = nil
                }
            } else {
                SoundManager.playUndo()
            }
            HabitTaskLink.setHabitCompleted(willBeCompleted, on: habit, now: now)
            // Keep any hour task created from this habit in step with it.
            if let tasks = try? modelContext.fetch(FetchDescriptor<TaskItem>()) {
                HabitTaskLink.applyHabitCompletionToTasks(habit, tasks: tasks, now: now)
            }
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
    
    private func deleteHabit() {
        SoundManager.playTaskDeleted()
        withAnimation {
            let now = Date()
            habit.deletedAt = now
            habit.updatedAt = now
            // Drop any hour tasks that still represent this habit.
            if let tasks = try? modelContext.fetch(FetchDescriptor<TaskItem>()) {
                _ = HabitTaskLink.binLinkedHourTasks(for: habit, tasks: tasks, now: now)
            }
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
}

// MARK: - Habit Drag & Drop Reordering

@MainActor
class HabitDragState: ObservableObject {
    static let shared = HabitDragState()
    @Published var draggedHabit: HabitItem?
}

struct HabitDropDelegate: DropDelegate {
    let item: HabitItem
    let context: ModelContext
    var proxy: ScrollViewProxy? = nil

    func dropEntered(info: DropInfo) {
        guard let draggedItem = HabitDragState.shared.draggedHabit else { return }
        if draggedItem.id != item.id {
            withAnimation(.easeInOut(duration: 0.2)) {
                let descriptor = FetchDescriptor<HabitItem>()
                guard let allHabits = try? context.fetch(descriptor) else { return }
                var sorted = allHabits.filter { $0.deletedAt == nil }.sorted { $0.order < $1.order }
                
                if let sourceIdx = sorted.firstIndex(where: { $0.id == draggedItem.id }),
                   let targetIdx = sorted.firstIndex(where: { $0.id == item.id }) {
                    let moved = sorted.remove(at: sourceIdx)
                    sorted.insert(moved, at: targetIdx)
                }
                
                for (i, h) in sorted.enumerated() {
                    h.order = i
                }
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy?.scrollTo(item.id, anchor: .center)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Persist reorder only once, at the end of the drag gesture
        if let draggedItem = HabitDragState.shared.draggedHabit {
            draggedItem.updatedAt = Date()
        }
        try? context.save()
        SupabaseSyncManager.shared.push()
        withAnimation(.easeInOut(duration: 0.15)) {
            HabitDragState.shared.draggedHabit = nil
        }
        return true
    }
}
