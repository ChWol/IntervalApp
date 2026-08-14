import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine
#if os(macOS)
import AppKit
#endif

// MARK: - Notification Names

extension Notification.Name {
    static let scratchpadClearSelection = Notification.Name("scratchpadClearSelection")
}

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
    @ObservedObject private var locManager = LocalizationManager.shared

    @Binding var focusedTaskId: String?

    @State private var selectedListId: String? = nil
    @State private var isCreatingList: Bool = false
    @State private var newListName: String = ""

    @State private var editingListTitleId: String? = nil
    @State private var editingListTitleText: String = ""
    @FocusState private var isEditingListTitleFocused: Bool

    @State private var listToDelete: ScratchpadList? = nil
    @State private var showDeleteListAlert: Bool = false

    @State private var selectedItemIds: Set<String> = []
    @State private var lastClickedItemId: String? = nil

    @FocusState private var isNewListFocused: Bool

    @State private var isNewListPlusHovered: Bool = false
    @State private var isCreateFirstListHovered: Bool = false
    @State private var isItemPlusHovered: Bool = false

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
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(activeLists) { list in
                            let isSelected = selectedList?.id == list.id

                            HStack(spacing: 6) {
                                if editingListTitleId == list.id {
                                    TextField("", text: $editingListTitleText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(minWidth: 60)
                                        .focused($isEditingListTitleFocused)
                                        .onSubmit {
                                            finishEditingListTitle(list)
                                        }
                                        .onChange(of: isEditingListTitleFocused) { _, focused in
                                            if !focused { finishEditingListTitle(list) }
                                        }
                                        #if os(macOS)
                                        .onExitCommand { finishEditingListTitle(list) }
                                        #endif
                                } else {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedListId = list.id
                                            selectedItemIds.removeAll()
                                            focusedTaskId = nil
                                        }
                                    }) {
                                        Text(list.title.isEmpty ? "Untitled List".localized : list.title)
                                            .font(.system(size: 12, weight: isSelected ? .medium : .light))
                                            .foregroundColor(isSelected ? .primary : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .pointingHandCursor()

                                    if isSelected {
                                        Button(action: {
                                            editingListTitleId = list.id
                                            editingListTitleText = list.title
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                isEditingListTitleFocused = true
                                            }
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .pointingHandCursor()
                                        .help("Edit list name")

                                        Button(action: {
                                            listToDelete = list
                                            showDeleteListAlert = true
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .pointingHandCursor()
                                    }
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
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .regular))
                                    Text("New List".localized)
                                        .font(.system(size: 11, weight: .light))
                                }
                                .foregroundColor(isNewListPlusHovered ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .stroke(isNewListPlusHovered ? Color.primary.opacity(0.4) : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3]))
                                )
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .onHover { hovering in
                                isNewListPlusHovered = hovering
                            }
                        } else {
                            HStack(spacing: 6) {
                                TextField("List name...".localized, text: $newListName)
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
                                .pointingHandCursor()
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
                    .padding(.trailing, 120)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 5)

            // MARK: - Selected List Contents or Empty State
            if activeLists.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    Text("No custom lists created yet.".localized)
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
                            Text("Create First List".localized)
                        }
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(isCreateFirstListHovered ? .primary : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(isCreateFirstListHovered ? 0.12 : 0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { hovering in
                        isCreateFirstListHovered = hovering
                    }
                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            } else if let currentList = selectedList {
                // MARK: - List Header with subtle + button
                HStack {
                    Text("ITEMS".localized)
                        .font(.system(size: 10, weight: .light, design: .default))
                        .tracking(2.0)
                        .foregroundColor(.gray)

                    Spacer()

                    Button(action: {
                        createNewItemAtEnd()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(isItemPlusHovered ? .primary : .secondary.opacity(0.6))
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { hovering in
                        isItemPlusHovered = hovering
                    }
                }
                .padding(.bottom, 2)

                // MARK: - Open Scratchpad Items List
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(openItems) { item in
                        ScratchpadItemRowView(
                            item: item,
                            isNew: false,
                            listId: currentList.id,
                            currentListId: currentList.id,
                            focusedTaskId: $focusedTaskId,
                            selectedItemIds: $selectedItemIds,
                            lastClickedItemId: $lastClickedItemId,
                            allItemsInList: openItems
                        )
                    }
                }

                // MARK: - Completed Items Section with Divider & Clear All
                if !completedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("\("COMPLETED".localized) (\(completedItems.count))")
                                .font(.system(size: 9, weight: .light, design: .default))
                                .tracking(1.5)
                                .foregroundColor(.secondary.opacity(0.7))

                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color.primary.opacity(0.06))

                            Button(action: {
                                clearAllCompletedItems(in: currentList.id)
                            }) {
                                Text("Clear All".localized)
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                        .padding(.top, 15)

                        ForEach(completedItems) { item in
                            ScratchpadItemRowView(
                                item: item,
                                isNew: false,
                                listId: currentList.id,
                                currentListId: currentList.id,
                                focusedTaskId: $focusedTaskId,
                                selectedItemIds: $selectedItemIds,
                                lastClickedItemId: $lastClickedItemId,
                                allItemsInList: completedItems
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, minHeight: 600, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            // Deselect all items & dismiss editing on any click anywhere
            focusedTaskId = nil
            selectedItemIds.removeAll()
            #if os(iOS)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
            if let currentList = selectedList {
                finishEditingListTitle(currentList)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scratchpadClearSelection)) { _ in
            selectedItemIds.removeAll()
            focusedTaskId = nil
            if let currentList = selectedList {
                finishEditingListTitle(currentList)
            }
        }
        #if os(macOS)
        .onExitCommand {
            selectedItemIds.removeAll()
            if let currentList = selectedList {
                finishEditingListTitle(currentList)
            }
        }
        #endif
        .background(
            Group {
                Button("") {
                    if focusedTaskId == nil {
                        selectedItemIds = Set(openItems.map { $0.id })
                    }
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("") {
                    if focusedTaskId == nil && !selectedItemIds.isEmpty {
                        copySelectedItems()
                    }
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("") {
                    selectedItemIds.removeAll()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        )
        .onAppear {
            if selectedListId == nil {
                selectedListId = activeLists.first?.id
            }
        }
        .alert("Delete List?".localized, isPresented: $showDeleteListAlert, presenting: listToDelete) { list in
            Button("Delete".localized, role: .destructive) {
                deleteList(list)
            }
            Button("Cancel".localized, role: .cancel) {}
        } message: { list in
            Text("Delete list message".localized)
        }
    }

    private func copySelectedItems() {
        let selected = openItems
            .filter { selectedItemIds.contains($0.id) }
            .sorted { $0.order < $1.order }
        let textToCopy = selected.map { $0.text }.joined(separator: "\n")
        guard !textToCopy.isEmpty else { return }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = textToCopy
        #endif
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
        if !trimmed.isEmpty {
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
    var currentListId: String
    @Binding var focusedTaskId: String?
    @Binding var selectedItemIds: Set<String>
    @Binding var lastClickedItemId: String?
    var allItemsInList: [ScratchpadItem]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var locManager = LocalizationManager.shared

    @Query(sort: \ScratchpadList.order) private var allLists: [ScratchpadList]

    @State private var text: String = ""
    @State private var isExpanded: Bool = false
    @State private var isHovering: Bool = false
    @State private var isArrowHovered: Bool = false
    @State private var isXHovered: Bool = false
    @State private var showTransferPopover: Bool = false
    #if os(macOS)
    @State private var escMonitor: Any? = nil
    #endif

    private var myId: String { item.id }
    private var isCurrentlyFocused: Bool { focusedTaskId == myId }
    private var isSelected: Bool { selectedItemIds.contains(myId) }
    private var isDragged: Bool { !isNew && ScratchpadDragState.shared.draggedItem?.id == item.id }

    private var otherLists: [ScratchpadList] {
        allLists.filter { $0.deletedAt == nil && $0.id != currentListId }
    }

    var body: some View {
        let rawText = isNew ? (text.isEmpty ? "Item...".localized : text) : (text.isEmpty ? item.text : text)
        let displayText = rawText
        let isPlaceholder = isNew && text.isEmpty

        Group {
            if isDragged {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .frame(height: 24)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Button(action: toggleCompleted) {
                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(item.completed ? .primary : .secondary)
                            .padding(.top, 3)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()

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
                                    handleTapSelection()
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
                                        let descriptor = FetchDescriptor<ScratchpadItem>()
                                        if let all = try? modelContext.fetch(descriptor) {
                                            let sorted = all.filter { $0.listId == listId && $0.deletedAt == nil && !$0.completed }.sorted { $0.order < $1.order }
                                            if let idx = sorted.firstIndex(where: { $0.id == item.id }), idx > 0 {
                                                let prevId = sorted[idx - 1].id
                                                DispatchQueue.main.async {
                                                    focusedTaskId = prevId
                                                }
                                            }
                                        }
                                        deleteItem()
                                    }
                                },
                                onPasteMultipleLines: { lines in
                                    handleMultiLinePaste(lines: lines)
                                },
                                fontSize: 14,
                                placeholder: isNew ? "Item...".localized : ""
                            )
                        }
                    }

                    if !isNew {
                        HStack(spacing: 2) {
                            if !item.completed {
                                Button(action: {
                                    showTransferPopover.toggle()
                                }) {
                                    Image(systemName: "arrow.turn.up.right")
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundColor(isArrowHovered ? .primary : .secondary.opacity(0.6))
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                .onHover { hovering in
                                    isArrowHovered = hovering
                                    if hovering { isHovering = true }
                                }
                                .popover(isPresented: $showTransferPopover, arrowEdge: .trailing) {
                                    transferPopoverContent
                                }
                            }

                            Button(action: deleteItem) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(isXHovered ? .primary : .secondary.opacity(0.6))
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .onHover { hovering in
                                isXHovered = hovering
                                if hovering { isHovering = true }
                            }
                        }
                        .opacity((isHovering || showTransferPopover || (isSelected && selectedItemIds.count > 1)) ? 1 : 0)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    (isSelected && selectedItemIds.count > 1)
                    ? RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    : nil
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                }
            }
        }
        .onAppear {
            text = item.text
        }
        .onChange(of: item.text) { _, newText in
            if !isCurrentlyFocused { text = newText }
        }
        .onChange(of: focusedTaskId) { oldId, newId in
            if oldId == myId && newId != myId {
                saveItem()
                if isExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = false
                    }
                }
            }
        }
        .onChange(of: showTransferPopover) { _, isShowing in
            #if os(macOS)
            if isShowing {
                escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 53 { // ESC key
                        showTransferPopover = false
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
        .onDrag {
            if !isNew {
                ScratchpadDragState.shared.draggedItem = item
                return NSItemProvider(object: item.id as NSString)
            }
            return NSItemProvider()
        }
        .onDrop(of: [.data], delegate: ScratchpadItemDropDelegate(item: item, context: modelContext))
    }

    // MARK: - Transfer Popover Content

    @ViewBuilder
    private var transferPopoverContent: some View {
        let multiCount: Int = selectedItemIds.contains(myId) && selectedItemIds.count > 1 ? selectedItemIds.count : 1

        VStack(alignment: .leading, spacing: 0) {
            // --- Section: Transfer to main screen ---
            Text("ADD TO MAIN".localized)
                .font(.system(size: 9, weight: .light))
                .tracking(1.8)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(["1 Hour", "1 Day", "1 Week", "1 Month", "1 Year"], id: \.self) { cat in
                    TransferPopoverRow(label: cat.localized) {
                        showTransferPopover = false
                        transferToMain(intervalType: cat)
                    }
                }
            }

            // --- Section: Move to another list (if any exist) ---
            if !otherLists.isEmpty {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                Text("MOVE TO LIST".localized)
                    .font(.system(size: 9, weight: .light))
                    .tracking(1.8)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                VStack(spacing: 0) {
                    ForEach(otherLists) { list in
                        TransferPopoverRow(label: list.title.isEmpty ? "Untitled List".localized : list.title) {
                            showTransferPopover = false
                            moveToList(targetListId: list.id)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 160)
        .overlay(alignment: .topTrailing) {
            if multiCount > 1 {
                Text("\(multiCount)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.6)))
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            }
        }
        #if os(macOS)
        .onExitCommand {
            showTransferPopover = false
        }
        #endif
        .background(
            Button("") {
                showTransferPopover = false
            }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
        )
    }

    // MARK: - Tap Selection

    private func handleTapSelection() {
        if isNew {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
                focusedTaskId = myId
            }
            return
        }

        #if os(macOS)
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedItemIds.contains(myId) {
                selectedItemIds.remove(myId)
            } else {
                selectedItemIds.insert(myId)
            }
            lastClickedItemId = myId
            return
        } else if flags.contains(.shift), let lastId = lastClickedItemId {
            let allIds = allItemsInList.map { $0.id }
            if let idx1 = allIds.firstIndex(of: lastId), let idx2 = allIds.firstIndex(of: myId) {
                let start = min(idx1, idx2)
                let end = max(idx1, idx2)
                for i in start...end {
                    selectedItemIds.insert(allIds[i])
                }
            }
            return
        }
        #endif

        // Any click without Command or Shift deselects all other items and selects ONLY this item
        selectedItemIds = [myId]
        lastClickedItemId = myId

        if !isExpanded {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
                focusedTaskId = myId
            }
        } else {
            focusedTaskId = myId
        }
    }

    // MARK: - Transfer / Move

    private func transferToMain(intervalType: String) {
        SoundManager.playTransfer()
        let itemsToTransfer: [ScratchpadItem]
        if selectedItemIds.contains(myId) && selectedItemIds.count > 1 {
            itemsToTransfer = allItemsInList.filter { selectedItemIds.contains($0.id) }
        } else {
            itemsToTransfer = [item]
        }

        let descriptor = FetchDescriptor<TaskItem>()
        let existingTasks = (try? modelContext.fetch(descriptor))?.filter { $0.intervalType == intervalType && $0.deletedAt == nil } ?? []
        var maxOrder = (existingTasks.map { $0.order }.max() ?? -1) + 1

        let now = Date()
        for scratchItem in itemsToTransfer {
            let newTask = TaskItem(text: scratchItem.text, intervalType: intervalType, order: maxOrder)
            modelContext.insert(newTask)
            maxOrder += 1
            scratchItem.deletedAt = now
            scratchItem.updatedAt = now
        }
        try? modelContext.save()
        SupabaseSyncManager.shared.push()
        selectedItemIds.removeAll()
    }

    private func moveToList(targetListId: String) {
        let itemsToMove: [ScratchpadItem]
        if selectedItemIds.contains(myId) && selectedItemIds.count > 1 {
            itemsToMove = allItemsInList.filter { selectedItemIds.contains($0.id) }
        } else {
            itemsToMove = [item]
        }

        let descriptor = FetchDescriptor<ScratchpadItem>()
        let allItems = (try? modelContext.fetch(descriptor)) ?? []
        let targetItems = allItems.filter { $0.listId == targetListId && $0.deletedAt == nil && !$0.completed }
        var maxOrder = (targetItems.map { $0.order }.max() ?? -1) + 1

        let now = Date()
        for scratchItem in itemsToMove {
            scratchItem.listId = targetListId
            scratchItem.order = maxOrder
            scratchItem.updatedAt = now
            maxOrder += 1
        }
        try? modelContext.save()
        SupabaseSyncManager.shared.push()
        selectedItemIds.removeAll()
    }

    private func toggleCompleted() {
        focusedTaskId = nil
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        if !item.completed {
            SoundManager.playTaskCompleted()
        } else {
            SoundManager.playUndo()
        }
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
        SoundManager.playTaskDeleted()
        let now = Date()
        let itemsToDelete: [ScratchpadItem]
        if selectedItemIds.contains(myId) && selectedItemIds.count > 1 {
            itemsToDelete = allItemsInList.filter { selectedItemIds.contains($0.id) }
        } else {
            itemsToDelete = [item]
        }

        for it in itemsToDelete {
            it.deletedAt = now
            it.updatedAt = now
        }
        try? modelContext.save()
        SupabaseSyncManager.shared.push()
        selectedItemIds.removeAll()
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

    private func handleMultiLinePaste(lines: [String]) {
        guard lines.count > 1 else { return }
        let trimmedFirst = lines[0].trimmingCharacters(in: .whitespaces)
        let rest = Array(lines.dropFirst()).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let descriptor = FetchDescriptor<ScratchpadItem>()
        guard let allItems = try? modelContext.fetch(descriptor) else { return }
        let now = Date()

        if isNew {
            let sorted = allItems
                .filter { $0.listId == listId && $0.deletedAt == nil && !$0.completed }
                .sorted { $0.order < $1.order }
            var nextOrder = (sorted.last?.order ?? -1) + 1

            if !trimmedFirst.isEmpty {
                let firstItem = ScratchpadItem(listId: listId, text: trimmedFirst, order: nextOrder)
                modelContext.insert(firstItem)
                nextOrder += 1
            }
            for line in rest {
                let newItem = ScratchpadItem(listId: listId, text: line, order: nextOrder)
                modelContext.insert(newItem)
                nextOrder += 1
            }

            let trailingNewItem = ScratchpadItem(listId: listId, text: "", order: nextOrder)
            modelContext.insert(trailingNewItem)

            try? modelContext.save()
            SupabaseSyncManager.shared.push()

            text = ""
            DispatchQueue.main.async {
                focusedTaskId = trailingNewItem.id
            }
        } else {
            item.text = trimmedFirst
            item.updatedAt = now
            text = trimmedFirst

            let sorted = allItems
                .filter { $0.listId == listId && $0.deletedAt == nil && !$0.completed }
                .sorted { $0.order < $1.order }

            var nextOrder = item.order + 1
            var lastCreatedItem: ScratchpadItem? = nil
            for line in rest {
                let newItem = ScratchpadItem(listId: listId, text: line, order: nextOrder)
                modelContext.insert(newItem)
                nextOrder += 1
                lastCreatedItem = newItem
            }

            let subsequentItems = sorted.filter { $0.order > item.order && $0.id != item.id }
            for subItem in subsequentItems {
                subItem.order = nextOrder
                nextOrder += 1
            }

            try? modelContext.save()
            SupabaseSyncManager.shared.push()

            if let lastId = lastCreatedItem?.id {
                DispatchQueue.main.async {
                    focusedTaskId = lastId
                }
            }
        }
    }
}

// MARK: - Transfer Popover Row

struct TransferPopoverRow: View {
    let label: String
    let onTap: () -> Void
    @State private var isHovered: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .light))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .padding(.horizontal, 4)
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
