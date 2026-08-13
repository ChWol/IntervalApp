import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine

// MARK: - Drag State for Scratchpad Items & Lists

class ScratchpadDragState: ObservableObject {
    static let shared = ScratchpadDragState()
    @Published var draggedItem: ScratchpadItem?
    @Published var draggedList: ScratchpadList?
}

// MARK: - Scratchpad Main View

struct ScratchpadView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @Query(sort: \ScratchpadList.order) private var lists: [ScratchpadList]
    @Query(sort: \ScratchpadItem.order) private var items: [ScratchpadItem]
    
    @Binding var focusedTaskId: String?
    
    @State private var selectedListId: String? = nil
    @State private var isCreatingList: Bool = false
    @State private var newListName: String = ""
    @State private var editingListTitleId: String? = nil
    @State private var editingListTitleText: String = ""
    @State private var listToDelete: ScratchpadList? = nil
    @State private var showDeleteListAlert: Bool = false
    @FocusState private var isNewListFocused: Bool
    
    private var activeLists: [ScratchpadList] {
        lists.filter { $0.deletedAt == nil }.sorted { $0.order < $1.order }
    }
    
    private var selectedList: ScratchpadList? {
        if let id = selectedListId, let list = activeLists.first(where: { $0.id == id }) {
            return list
        }
        return activeLists.first
    }
    
    private var activeItems: [ScratchpadItem] {
        guard let listId = selectedList?.id else { return [] }
        return items.filter { $0.listId == listId && $0.deletedAt == nil }
    }
    
    private var openItems: [ScratchpadItem] {
        activeItems.filter { !$0.completed }.sorted { $0.order < $1.order }
    }
    
    private var completedItems: [ScratchpadItem] {
        activeItems.filter { $0.completed }.sorted { ($0.completedAt ?? Date.distantPast) > ($1.completedAt ?? Date.distantPast) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // MARK: - List Selector Bar (Chips & New List Button)
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(activeLists) { list in
                            let isSelected = selectedList?.id == list.id
                            
                            HStack(spacing: 6) {
                                if editingListTitleId == list.id {
                                    TextField("List title...", text: $editingListTitleText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(minWidth: 60)
                                        .onSubmit {
                                            finishEditingListTitle(list)
                                        }
                                } else {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedListId = list.id
                                        }
                                    }) {
                                        Text(list.title.isEmpty ? "Untitled List" : list.title)
                                            .font(.system(size: 12, weight: isSelected ? .medium : .light))
                                            .foregroundColor(isSelected ? .primary : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .onTapGesture(count: 2) {
                                        editingListTitleId = list.id
                                        editingListTitleText = list.title
                                    }
                                }
                                
                                if isSelected {
                                    Button(action: {
                                        listToDelete = list
                                        showDeleteListAlert = true
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08) : Color.clear)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(isSelected ? 0.2 : 0.08), lineWidth: 1)
                            )
                            .onDrag {
                                ScratchpadDragState.shared.draggedList = list
                                return NSItemProvider(object: list.id as NSString)
                            }
                            .onDrop(of: [.data], delegate: ScratchpadListDropDelegate(item: list, context: modelContext))
                        }
                        
                        if !isCreatingList {
                            Button(action: {
                                withAnimation { isCreatingList = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    isNewListFocused = true
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .light))
                                    Text("New List")
                                        .font(.system(size: 11, weight: .light))
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3]))
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            HStack(spacing: 6) {
                                TextField("List name...", text: $newListName)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, weight: .light))
                                    .frame(width: 100)
                                    .focused($isNewListFocused)
                                    .onSubmit { createList() }
                                    .onChange(of: isNewListFocused) { _, focused in
                                        if !focused {
                                            let trimmed = newListName.trimmingCharacters(in: .whitespaces)
                                            if trimmed.isEmpty {
                                                withAnimation {
                                                    isCreatingList = false
                                                    newListName = ""
                                                }
                                            } else {
                                                createList()
                                            }
                                        }
                                    }
                                    #if os(macOS)
                                    .onExitCommand {
                                        withAnimation {
                                            isCreatingList = false
                                            newListName = ""
                                        }
                                    }
                                    #endif
                                
                                Button(action: createList) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9))
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(0.12))
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(.bottom, 5)
            
            // MARK: - Selected List Contents or Empty State
            if activeLists.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    Text("No custom lists created yet.")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        withAnimation { isCreatingList = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isNewListFocused = true
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Create First List")
                        }
                        .font(.system(size: 12, weight: .light))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            } else if let currentList = selectedList {
                HStack {
                    Text(currentList.title.uppercased())
                        .font(.system(size: 10, weight: .light, design: .default))
                        .tracking(2.0)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Button(action: { createNewItemAtEnd() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .light))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                
                // MARK: - Open Scratchpad Items List
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(openItems) { item in
                        ScratchpadItemRowView(
                            item: item,
                            isNew: false,
                            listId: currentList.id,
                            focusedTaskId: $focusedTaskId
                        )
                    }
                    
                    if openItems.isEmpty && completedItems.isEmpty {
                        ScratchpadItemRowView(
                            item: ScratchpadItem(listId: currentList.id, text: ""),
                            isNew: true,
                            listId: currentList.id,
                            focusedTaskId: $focusedTaskId
                        )
                    }
                }
                
                // MARK: - Completed Items Section with Divider & Clear All
                if !completedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("COMPLETED (\(completedItems.count))")
                                .font(.system(size: 9, weight: .light, design: .default))
                                .tracking(1.5)
                                .foregroundColor(.secondary.opacity(0.7))
                            
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color.primary.opacity(0.06))
                            
                            Button(action: {
                                clearAllCompletedItems(in: currentList.id)
                            }) {
                                Text("Clear All")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 15)
                        
                        ForEach(completedItems) { item in
                            ScratchpadItemRowView(
                                item: item,
                                isNew: false,
                                listId: currentList.id,
                                focusedTaskId: $focusedTaskId
                            )
                        }
                    }
                }
            }
            
            Spacer(minLength: 20)
        }
        .onAppear {
            if selectedListId == nil {
                selectedListId = activeLists.first?.id
            }
        }
        .alert("Delete List?", isPresented: $showDeleteListAlert, presenting: listToDelete) { list in
            Button("Delete", role: .destructive) {
                deleteList(list)
            }
            Button("Cancel", role: .cancel) {}
        } message: { list in
            Text("Are you sure you want to delete '\(list.title.isEmpty ? "Untitled List" : list.title)' and all its items?")
        }
    }
    
    private func createList() {
        let trimmed = newListName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            withAnimation { isCreatingList = false }
            return
        }
        newListName = ""
        let maxOrder = (activeLists.map { $0.order }.max() ?? -1) + 1
        let newList = ScratchpadList(title: trimmed, order: maxOrder)
        modelContext.insert(newList)
        try? modelContext.save()
        SupabaseSyncManager.shared.push()
        withAnimation {
            isCreatingList = false
            selectedListId = newList.id
        }
    }
    
    private func finishEditingListTitle(_ list: ScratchpadList) {
        let trimmed = editingListTitleText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && list.title != trimmed {
            list.title = trimmed
            list.updatedAt = Date()
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
        editingListTitleId = nil
    }
    
    private func deleteList(_ list: ScratchpadList) {
        list.deletedAt = Date()
        list.updatedAt = Date()
        for item in items where item.listId == list.id {
            item.deletedAt = Date()
            item.updatedAt = Date()
        }
        try? modelContext.save()
        SupabaseSyncManager.shared.push()
        if selectedListId == list.id {
            selectedListId = activeLists.first(where: { $0.id != list.id })?.id
        }
    }
    
    private func createNewItemAtEnd() {
        guard let currentList = selectedList else { return }
        let maxOrder = (openItems.map { $0.order }.max() ?? -1) + 1
        let newItem = ScratchpadItem(listId: currentList.id, text: "", order: maxOrder)
        modelContext.insert(newItem)
        try? modelContext.save()
        SupabaseSyncManager.shared.push()
        DispatchQueue.main.async {
            focusedTaskId = newItem.id
        }
    }
    
    private func clearAllCompletedItems(in listId: String) {
        let now = Date()
        withAnimation {
            for item in completedItems {
                item.deletedAt = now
                item.updatedAt = now
            }
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
}

// MARK: - Scratchpad Item Row Component

struct ScratchpadItemRowView: View {
    @Bindable var item: ScratchpadItem
    var isNew: Bool
    var listId: String
    @Binding var focusedTaskId: String?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var text: String = ""
    @State private var isExpanded: Bool = false
    @State private var isHovered: Bool = false
    
    private var myId: String { item.id }
    private var isCurrentlyFocused: Bool { focusedTaskId == myId }
    private var isDragged: Bool { !isNew && ScratchpadDragState.shared.draggedItem?.id == item.id }
    
    var body: some View {
        let displayText = text.isEmpty ? (isNew ? "New item..." : "Item...") : text
        let isPlaceholder = text.isEmpty
        
        ZStack {
            if isDragged {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .frame(height: 24)
            }
            
            HStack(alignment: .top, spacing: 8) {
                Button(action: toggleCompleted) {
                    Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(item.completed ? .primary : .secondary)
                        .padding(.top, 3)
                }
                .buttonStyle(.plain)
                
                ZStack(alignment: .topLeading) {
                    if !isCurrentlyFocused {
                        Text(displayText)
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(isPlaceholder ? .secondary.opacity(0.5) : (item.completed ? .secondary : .primary))
                            .strikethrough(item.completed)
                            .lineLimit(isExpanded ? nil : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isExpanded {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isExpanded = true
                                        focusedTaskId = myId
                                    }
                                } else {
                                    focusedTaskId = myId
                                }
                            }
                    } else {
                        CustomTextField(
                            text: $text,
                            isFocused: isCurrentlyFocused,
                            onFocusChanged: { focused in
                                if focused {
                                    focusedTaskId = myId
                                } else {
                                    if focusedTaskId == myId {
                                        focusedTaskId = nil
                                    }
                                    saveItem()
                                }
                            },
                            onSubmit: { isAtBeginning in
                                handleItemSubmit(isAtBeginning: isAtBeginning)
                            },
                            onDeleteEmpty: {
                                if !isNew {
                                    deleteItem()
                                }
                            },
                            fontSize: 14,
                            placeholder: isNew ? "New item..." : "Item..."
                        )
                    }
                }
                
                if !isNew {
                    Button(action: deleteItem) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                }
            }
            .opacity(isDragged ? 0 : 1)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            text = item.text
        }
        .onChange(of: item.text) { _, newText in
            if !isCurrentlyFocused { text = newText }
        }
        .onChange(of: focusedTaskId) { _, newId in
            if newId != myId && isExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
        }
        .onDrag {
            if !isNew {
                ScratchpadDragState.shared.draggedItem = item
                return NSItemProvider(object: item.id as NSString)
            }
            return NSItemProvider()
        }
        .onDrop(of: [.data], delegate: ScratchpadItemDropDelegate(item: item, context: modelContext))
    }
    
    private func toggleCompleted() {
        focusedTaskId = nil
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        withAnimation(.easeOut(duration: 0.2)) {
            item.completed.toggle()
            item.completedAt = item.completed ? Date() : nil
            item.updatedAt = Date()
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
    
    private func saveItem() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if isNew {
            if !trimmed.isEmpty {
                let descriptor = FetchDescriptor<ScratchpadItem>()
                if let all = try? modelContext.fetch(descriptor) {
                    let sorted = all.filter { $0.listId == listId && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                    let newItem = ScratchpadItem(listId: listId, text: trimmed, order: (sorted.last?.order ?? -1) + 1)
                    modelContext.insert(newItem)
                    try? modelContext.save()
                    SupabaseSyncManager.shared.push()
                    text = ""
                }
            }
        } else {
            if trimmed.isEmpty {
                deleteItem()
            } else if item.text != trimmed {
                item.text = trimmed
                item.updatedAt = Date()
                try? modelContext.save()
                SupabaseSyncManager.shared.push()
            }
        }
    }
    
    private func deleteItem() {
        item.deletedAt = Date()
        item.updatedAt = Date()
        try? modelContext.save()
        SupabaseSyncManager.shared.push()
    }
    
    private func handleItemSubmit(isAtBeginning: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if isNew {
            if !trimmed.isEmpty {
                let descriptor = FetchDescriptor<ScratchpadItem>()
                if let all = try? modelContext.fetch(descriptor) {
                    let sorted = all.filter { $0.listId == listId && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                    let newItem = ScratchpadItem(listId: listId, text: trimmed, order: (sorted.last?.order ?? -1) + 1)
                    modelContext.insert(newItem)
                    
                    let nextItem = ScratchpadItem(listId: listId, text: "", order: newItem.order + 1)
                    modelContext.insert(nextItem)
                    try? modelContext.save()
                    SupabaseSyncManager.shared.push()
                    text = ""
                    DispatchQueue.main.async {
                        focusedTaskId = nextItem.id
                    }
                }
            }
        } else {
            if trimmed.isEmpty {
                deleteItem()
            } else {
                item.text = trimmed
                item.updatedAt = Date()
                
                let descriptor = FetchDescriptor<ScratchpadItem>()
                if let all = try? modelContext.fetch(descriptor) {
                    var sorted = all.filter { $0.listId == listId && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                    let newItem = ScratchpadItem(listId: listId, text: "", order: item.order)
                    modelContext.insert(newItem)
                    
                    if let idx = sorted.firstIndex(where: { $0.id == item.id }) {
                        if isAtBeginning {
                            sorted.insert(newItem, at: idx)
                        } else {
                            sorted.insert(newItem, at: idx + 1)
                        }
                    } else {
                        sorted.append(newItem)
                    }
                    
                    let now = Date()
                    for (i, it) in sorted.enumerated() {
                        it.order = i
                        it.updatedAt = now
                    }
                    try? modelContext.save()
                    SupabaseSyncManager.shared.push()
                    DispatchQueue.main.async {
                        focusedTaskId = newItem.id
                    }
                }
            }
        }
    }
}

// MARK: - Drop Delegates for Scratchpad Items & Lists

struct ScratchpadItemDropDelegate: DropDelegate {
    let item: ScratchpadItem
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let draggedItem = ScratchpadDragState.shared.draggedItem else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            if draggedItem.id != item.id || draggedItem.listId != item.listId {
                draggedItem.listId = item.listId
                let descriptor = FetchDescriptor<ScratchpadItem>()
                guard let all = try? context.fetch(descriptor) else { return }
                var sorted = all.filter { $0.listId == item.listId && $0.deletedAt == nil && !$0.completed && $0.id != draggedItem.id }.sorted { $0.order < $1.order }
                
                if let targetIdx = sorted.firstIndex(where: { $0.id == item.id }) {
                    sorted.insert(draggedItem, at: targetIdx)
                } else {
                    sorted.append(draggedItem)
                }
                
                for (i, it) in sorted.enumerated() {
                    it.order = i
                }
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        let descriptor = FetchDescriptor<ScratchpadItem>()
        if let all = try? context.fetch(descriptor) {
            let now = Date()
            for it in all {
                it.updatedAt = now
            }
        }
        try? context.save()
        SupabaseSyncManager.shared.push()
        withAnimation(.easeInOut(duration: 0.15)) {
            ScratchpadDragState.shared.draggedItem = nil
        }
        return true
    }
}

struct ScratchpadListDropDelegate: DropDelegate {
    let item: ScratchpadList
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let draggedList = ScratchpadDragState.shared.draggedList else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            if draggedList.id != item.id {
                let descriptor = FetchDescriptor<ScratchpadList>()
                guard let all = try? context.fetch(descriptor) else { return }
                var sorted = all.filter { $0.deletedAt == nil && $0.id != draggedList.id }.sorted { $0.order < $1.order }
                
                if let targetIdx = sorted.firstIndex(where: { $0.id == item.id }) {
                    sorted.insert(draggedList, at: targetIdx)
                } else {
                    sorted.append(draggedList)
                }
                
                for (i, l) in sorted.enumerated() {
                    l.order = i
                }
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        let descriptor = FetchDescriptor<ScratchpadList>()
        if let all = try? context.fetch(descriptor) {
            let now = Date()
            for l in all {
                l.updatedAt = now
            }
        }
        try? context.save()
        SupabaseSyncManager.shared.push()
        withAnimation(.easeInOut(duration: 0.15)) {
            ScratchpadDragState.shared.draggedList = nil
        }
        return true
    }
}
