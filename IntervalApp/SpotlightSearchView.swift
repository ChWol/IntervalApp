import SwiftUI
import SwiftData

enum SearchTargetDestination: Hashable {
    case interval(intervalType: String)
    case habit
    case scratchpad(listId: String)
}

struct SearchResultItem: Identifiable, Hashable {
    let id: String
    let title: String
    let badge: String
    let isCompleted: Bool
    let isDeleted: Bool
    let destination: SearchTargetDestination
    let targetId: String
}

struct SpotlightSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var locManager = LocalizationManager.shared
    
    @Binding var isPresented: Bool
    let onSelect: (SearchResultItem) -> Void
    
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isFieldFocused: Bool
    
    @Query private var tasks: [TaskItem]
    @Query private var habits: [HabitItem]
    @Query private var scratchpadItems: [ScratchpadItem]
    @Query private var scratchpadLists: [ScratchpadList]
    
    private var results: [SearchResultItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        
        var listMap: [String: String] = [:]
        for l in scratchpadLists {
            listMap[l.id] = l.title
        }
        
        var items: [SearchResultItem] = []
        
        // 1. Tasks (Active, Completed, Deleted)
        let activeTasks = tasks.filter { $0.deletedAt == nil && !$0.completed && $0.text.lowercased().contains(q) }
        for t in activeTasks {
            let badge = t.intervalType.uppercased().localized
            items.append(SearchResultItem(
                id: "task-\(t.id)",
                title: t.text,
                badge: badge,
                isCompleted: false,
                isDeleted: false,
                destination: .interval(intervalType: t.intervalType),
                targetId: t.id
            ))
        }
        
        // 2. Habits
        let matchingHabits = habits.filter { $0.deletedAt == nil && $0.text.lowercased().contains(q) }
        for h in matchingHabits {
            items.append(SearchResultItem(
                id: "habit-\(h.id)",
                title: h.text,
                badge: "HABITS".localized,
                isCompleted: h.isCompletedCurrentPeriod,
                isDeleted: false,
                destination: .habit,
                targetId: h.id
            ))
        }
        
        // 3. Scratchpad Items
        let matchingScratchItems = scratchpadItems.filter { $0.deletedAt == nil && !$0.completed && $0.text.lowercased().contains(q) }
        for s in matchingScratchItems {
            let listName = listMap[s.listId] ?? "Untitled List".localized
            let badge = "SCRATCHPAD".localized + " • " + listName
            items.append(SearchResultItem(
                id: "scratch-\(s.id)",
                title: s.text,
                badge: badge,
                isCompleted: false,
                isDeleted: false,
                destination: .scratchpad(listId: s.listId),
                targetId: s.id
            ))
        }
        
        // 4. Completed Tasks
        let completedTasks = tasks.filter { $0.deletedAt == nil && $0.completed && $0.text.lowercased().contains(q) }
        for t in completedTasks {
            let badge = "COMPLETED".localized + " • " + t.intervalType.uppercased().localized
            items.append(SearchResultItem(
                id: "task-comp-\(t.id)",
                title: t.text,
                badge: badge,
                isCompleted: true,
                isDeleted: false,
                destination: .interval(intervalType: t.intervalType),
                targetId: t.id
            ))
        }
        
        // 5. Deleted Tasks
        let deletedTasks = tasks.filter { $0.deletedAt != nil && $0.text.lowercased().contains(q) }
        for t in deletedTasks {
            let badge = "RECENTLY DELETED".localized
            items.append(SearchResultItem(
                id: "task-del-\(t.id)",
                title: t.text,
                badge: badge,
                isCompleted: t.completed,
                isDeleted: true,
                destination: .interval(intervalType: t.intervalType),
                targetId: t.id
            ))
        }
        
        return items
    }
    
    var body: some View {
        ZStack {
            // Ambient Backdrop
            Color.black.opacity(colorScheme == .dark ? 0.65 : 0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    closeSearch()
                }
            
            VStack(spacing: 0) {
                #if os(macOS)
                spotlightPanel
                    .frame(maxWidth: 580)
                    .padding(.top, 90)
                Spacer()
                #else
                VStack(spacing: 0) {
                    // Grabber handle for iOS
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                    
                    spotlightPanel
                        .frame(maxWidth: .infinity)
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.98))
                        .shadow(color: Color.black.opacity(0.2), radius: 25, y: 10)
                )
                .padding(.horizontal, 12)
                .padding(.top, 50)
                Spacer()
                #endif
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .onAppear {
            isFieldFocused = true
            selectedIndex = 0
            #if os(macOS)
            setupKeyboardMonitor()
            #endif
        }
        .onDisappear {
            #if os(macOS)
            removeKeyboardMonitor()
            #endif
        }
    }
    
    private var spotlightPanel: some View {
        VStack(spacing: 0) {
            // Search Input Row
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(.secondary)
                
                TextField("Search tasks, habits, lists...".localized, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .light))
                    .focused($isFieldFocused)
                    .onSubmit {
                        commitSelection()
                    }
                    .onChange(of: query) { _, _ in
                        selectedIndex = 0
                    }
                
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                
                #if os(iOS)
                Button("Cancel".localized) {
                    closeSearch()
                }
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
                #endif
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            
            // Divider
            Divider()
                .opacity(0.3)
            
            // Results list or Empty State
            if query.isEmpty {
                VStack(spacing: 8) {
                    Text("Type to search across all intervals, habits & lists".localized)
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 32)
                }
                .frame(maxWidth: .infinity)
            } else if results.isEmpty {
                VStack(spacing: 8) {
                    Text("No results found".localized)
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.vertical, 28)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                resultRow(item: item, isSelected: index == selectedIndex)
                                    .id(item.id)
                                    .onTapGesture {
                                        selectedIndex = index
                                        commitSelection()
                                    }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selectedIndex) { _, newIdx in
                        if newIdx >= 0 && newIdx < results.count {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(results[newIdx].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.12).opacity(0.98) : Color(white: 0.98).opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 28, y: 12)
        )
        #endif
    }
    
    private func resultRow(item: SearchResultItem, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Icon / Status indicator
            if item.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            } else if item.isDeleted {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                    .frame(width: 6, height: 6)
                    .frame(width: 16)
            }
            
            // Item text
            Text(item.title)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(item.isCompleted ? .secondary : .primary)
                .strikethrough(item.isCompleted)
                .lineLimit(1)
            
            Spacer()
            
            // Badge / Context Tag
            Text(item.badge)
                .font(.system(size: 9, weight: .regular))
                .tracking(0.5)
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08) : Color.clear)
        )
        .contentShape(Rectangle())
    }
    
    private func commitSelection() {
        guard !results.isEmpty else { return }
        let validIndex = max(0, min(selectedIndex, results.count - 1))
        let item = results[validIndex]
        closeSearch()
        onSelect(item)
    }
    
    private func closeSearch() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isPresented = false
            query = ""
        }
    }
    
    #if os(macOS)
    @State private var eventMonitor: Any?
    
    private func setupKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isPresented else { return event }
            
            switch event.keyCode {
            case 126: // Up Arrow
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    return nil
                }
            case 125: // Down Arrow
                if selectedIndex < results.count - 1 {
                    selectedIndex += 1
                    return nil
                }
            case 36, 76: // Return / Enter
                if !results.isEmpty {
                    commitSelection()
                    return nil
                }
            case 53: // Escape
                closeSearch()
                return nil
            default:
                break
            }
            return event
        }
    }
    
    private func removeKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    #endif
}
