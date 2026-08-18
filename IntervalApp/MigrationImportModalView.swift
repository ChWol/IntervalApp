import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Migration Import Modal View

struct MigrationImportModalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    
    @State private var selectedSource: ImportSource = .tickTick
    @State private var isTargetedForDrop = false
    @State private var errorMessage: String?
    @State private var isParsing = false
    
    // Parsed Data for Kanban review
    @State private var parsedTasks: [ImportedTask] = []
    @State private var parsedScratchpadLists: [ImportedScratchpadList] = []
    @State private var step: ImportStep = .upload
    @State private var isFileImporterPresented = false
    
    // Dragged item state for Kanban
    @State private var draggedTaskId: String?
    
    enum ImportStep {
        case upload
        case kanbanReview
    }
    
    let intervalColumns = ["1 Day", "1 Week", "1 Month", "1 Year"]
    
    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.75 : 0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    if step == .upload {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step == .upload ? "IMPORT TASKS & LISTS".localized : "REVIEW & CATEGORIZE".localized)
                            .font(.system(size: 11, weight: .light))
                            .tracking(2.0)
                            .foregroundColor(.secondary)
                        
                        Text(step == .upload ? "Migrate from your existing apps".localized : "Drag tasks into your preferred intervals".localized)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                Divider()
                    .opacity(0.15)
                
                // Content
                if step == .upload {
                    uploadStepView
                } else {
                    kanbanStepView
                }
            }
            .frame(maxWidth: step == .upload ? 620 : 920, maxHeight: step == .upload ? 580 : 720)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 24, y: 12)
            )
            .padding(24)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .json, .plainText, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    processFile(at: url)
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Step 1: Upload & Instructions
    
    @ViewBuilder
    private var uploadStepView: some View {
        VStack(spacing: 20) {
            // Source Selector Tabs
            HStack(spacing: 6) {
                ForEach(ImportSource.allCases) { source in
                    let isSelected = selectedSource == source
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSource = source
                        }
                    }) {
                        Text(source.rawValue)
                            .font(.system(size: 12, weight: isSelected ? .medium : .light))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.08) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)
            
            // Instructions Box
            VStack(alignment: .leading, spacing: 10) {
                Text("HOW TO EXPORT:".localized)
                    .font(.system(size: 10, weight: .light))
                    .tracking(1.5)
                    .foregroundColor(.secondary)
                
                ForEach(Array(selectedSource.exportInstructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        
                        Text(instruction.localized)
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03))
            )
            .padding(.horizontal, 28)
            
            // Drop Zone / File Picker
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isTargetedForDrop ? Color.primary : Color.primary.opacity(0.15),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isTargetedForDrop ? Color.primary.opacity(0.05) : Color.clear)
                    )
                
                VStack(spacing: 12) {
                    if isParsing {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Analyzing tasks and lists...".localized)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 4) {
                            Text("Drag & drop your export file here".localized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Text("Supported formats: .csv, .json, .ics".localized)
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: {
                            isFileImporterPresented = true
                        }) {
                            Text("Choose File...".localized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(Color.primary)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(24)
            }
            .frame(height: 180)
            .padding(.horizontal, 28)
            .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.processFile(at: url)
                        }
                    }
                }
                return true
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(.red)
                    .padding(.horizontal, 28)
            }
            
            Spacer()
        }
        .padding(.bottom, 24)
    }
    
    // MARK: - Step 2: Kanban Drag & Drop Review Board
    
    @ViewBuilder
    private var kanbanStepView: some View {
        VStack(spacing: 16) {
            // Summary Counter Bar
            HStack(spacing: 16) {
                let totalTasks = parsedTasks.filter { $0.isSelected }.count
                let totalLists = parsedScratchpadLists.filter { $0.isSelected }.count
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("\(totalTasks) \("Interval Tasks".localized) • \(totalLists) \("Scratchpad Lists".localized)")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        step = .upload
                    }
                }) {
                    Text("Change File".localized)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            
            // Horizontal Kanban Columns
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    // 1. Interval Columns (1 Day, 1 Week, 1 Month, 1 Year)
                    ForEach(intervalColumns, id: \.self) { col in
                        kanbanIntervalColumn(interval: col)
                    }
                    
                    // 2. Scratchpad Lists Column
                    kanbanScratchpadColumn
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)
            
            Divider()
                .opacity(0.15)
            
            // Bottom Action Bar
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        step = .upload
                    }
                }) {
                    Text("Cancel".localized)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {
                    commitImport()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                        Text("IMPORT EVERYTHING".localized)
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1.0)
                    }
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(Color.primary)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Kanban Column for Intervals
    
    @ViewBuilder
    private func kanbanIntervalColumn(interval: String) -> some View {
        let tasksInCol = parsedTasks.filter { $0.targetInterval == interval }
        
        VStack(alignment: .leading, spacing: 10) {
            // Column Header
            HStack {
                Text(interval.uppercased().localized)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(tasksInCol.count)")
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            
            // Droppable Task List
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    if tasksInCol.isEmpty {
                        VStack(spacing: 6) {
                            Text("No tasks".localized)
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        ForEach(tasksInCol) { task in
                            KanbanTaskCardView(
                                task: task,
                                intervalColumns: intervalColumns,
                                onToggleSelected: {
                                    if let idx = parsedTasks.firstIndex(where: { $0.id == task.id }) {
                                        parsedTasks[idx].isSelected.toggle()
                                    }
                                },
                                onMove: { targetIntv in
                                    if let idx = parsedTasks.firstIndex(where: { $0.id == task.id }) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            parsedTasks[idx].targetInterval = targetIntv
                                        }
                                    }
                                },
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        parsedTasks.removeAll(where: { $0.id == task.id })
                                    }
                                },
                                onDragStart: {
                                    self.draggedTaskId = task.id
                                }
                            )
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 175)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03))
        )
        .onDrop(of: [.text], isTargeted: nil) { _ in
            guard let droppedId = draggedTaskId,
                  let idx = parsedTasks.firstIndex(where: { $0.id == droppedId }) else { return false }
            withAnimation(.easeInOut(duration: 0.15)) {
                parsedTasks[idx].targetInterval = interval
                draggedTaskId = nil
            }
            return true
        }
    }
    
    // MARK: - Scratchpad Lists Column
    
    @ViewBuilder
    private var kanbanScratchpadColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("SCRATCHPAD LISTS".localized)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(parsedScratchpadLists.count)")
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    if parsedScratchpadLists.isEmpty {
                        VStack(spacing: 6) {
                            Text("No custom lists".localized)
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        ForEach(parsedScratchpadLists) { list in
                            KanbanScratchpadListCardView(
                                list: list,
                                onToggleSelected: {
                                    if let idx = parsedScratchpadLists.firstIndex(where: { $0.id == list.id }) {
                                        parsedScratchpadLists[idx].isSelected.toggle()
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03))
        )
    }
    
    // MARK: - Actions
    
    private func processFile(at url: URL) {
        isParsing = true
        errorMessage = nil
        
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        
        Task {
            do {
                let analysis = try ImportManager.shared.parseFile(at: url)
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
                
                await MainActor.run {
                    self.isParsing = false
                    self.parsedTasks = analysis.intervalTasks
                    self.parsedScratchpadLists = analysis.scratchpadLists
                    self.selectedSource = analysis.detectedSource
                    
                    if analysis.totalCount == 0 {
                        self.errorMessage = "No tasks or lists found in the file.".localized
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.step = .kanbanReview
                        }
                    }
                }
            } catch {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
                await MainActor.run {
                    self.isParsing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func commitImport() {
        ImportManager.shared.commitImport(
            tasks: parsedTasks,
            scratchpadLists: parsedScratchpadLists,
            context: modelContext
        )
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

// MARK: - Kanban Subviews

struct KanbanTaskCardView: View {
    let task: ImportedTask
    let intervalColumns: [String]
    let onToggleSelected: () -> Void
    let onMove: (String) -> Void
    let onDelete: () -> Void
    let onDragStart: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Button(action: onToggleSelected) {
                    Image(systemName: task.isSelected ? "checkmark.square" : "square")
                        .font(.system(size: 11))
                        .foregroundColor(task.isSelected ? .primary : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                
                Text(task.text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(task.isSelected ? .primary : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
                
                Menu {
                    ForEach(intervalColumns, id: \.self) { intv in
                        Button(action: { onMove(intv) }) {
                            HStack {
                                Text(intv.localized)
                                if task.targetInterval == intv {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: onDelete) {
                        Text("Delete".localized)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(2)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 14)
            }
            
            if let due = task.dueDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9))
                    Text(formattedDate(due))
                        .font(.system(size: 10, weight: .light))
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        )
        .opacity(task.isSelected ? 1.0 : 0.5)
        .onDrag {
            onDragStart()
            return NSItemProvider(object: task.id as NSString)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        return df.string(from: date)
    }
}

struct KanbanScratchpadListCardView: View {
    let list: ImportedScratchpadList
    let onToggleSelected: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: onToggleSelected) {
                    Image(systemName: list.isSelected ? "checkmark.square" : "square")
                        .font(.system(size: 11))
                        .foregroundColor(list.isSelected ? .primary : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                
                Text(list.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(list.isSelected ? .primary : .secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(list.items.count)")
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(.secondary)
            }
            
            ForEach(list.items.prefix(2), id: \.id) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 4, height: 4)
                    Text(item.text)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            if list.items.count > 2 {
                Text("+ \(list.items.count - 2) \("more items".localized)")
                    .font(.system(size: 9, weight: .light))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.leading, 8)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        )
        .opacity(list.isSelected ? 1.0 : 0.5)
    }
}
