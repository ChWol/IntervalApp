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
    @State private var draggingTaskId: String? = nil
    @State private var dragPosition: CGPoint = .zero
    @State private var hoveredColumn: String? = nil
    @State private var columnFrames: [String: CGRect] = [:]
    
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
                        
                        Text(step == .upload ? "Migrate from your existing apps".localized : "Drag tasks between intervals to organize".localized)
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
                    .pointingHandCursor()
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
            .frame(maxWidth: step == .upload ? 620 : 960, maxHeight: step == .upload ? 580 : 720)
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
                    .pointingHandCursor()
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
                        .pointingHandCursor()
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
                let totalTasks = parsedTasks.count
                let totalLists = parsedScratchpadLists.count
                
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
                        .underline()
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            
            // Horizontal Kanban Columns with Direct-Manipulation Dragging
            ZStack(alignment: .topLeading) {
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
                
                // Floating card during dynamic drag
                if let draggingId = draggingTaskId,
                   let dragging = parsedTasks.first(where: { $0.id == draggingId }) {
                    FloatingKanbanTaskCardView(task: dragging)
                        .position(dragPosition)
                        .zIndex(999)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "kanbanCoordinateSpace")
            .onPreferenceChange(ColumnFramePreferenceKey.self) { frames in
                self.columnFrames = frames
            }
            
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
                .pointingHandCursor()
                
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
                .pointingHandCursor()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Kanban Column for Intervals
    
    @ViewBuilder
    private func kanbanIntervalColumn(interval: String) -> some View {
        let tasksInCol = parsedTasks.filter { $0.targetInterval == interval }
        let isHovered = hoveredColumn == interval
        
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
            
            // Task List
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    if tasksInCol.isEmpty {
                        VStack(spacing: 6) {
                            Text("No tasks".localized)
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ForEach(tasksInCol) { task in
                            KanbanTaskCardView(
                                task: task,
                                isDragging: draggingTaskId == task.id,
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        parsedTasks.removeAll(where: { $0.id == task.id })
                                    }
                                },
                                onDragChanged: { loc in
                                    self.draggingTaskId = task.id
                                    self.dragPosition = loc
                                    self.updateHoveredColumn(at: loc)
                                },
                                onDragEnded: {
                                    if let target = hoveredColumn, let draggingId = draggingTaskId {
                                        if let idx = parsedTasks.firstIndex(where: { $0.id == draggingId }) {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                                parsedTasks[idx].targetInterval = target
                                            }
                                        }
                                    }
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                        self.draggingTaskId = nil
                                        self.hoveredColumn = nil
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
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08) : Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isHovered ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 1.5)
                )
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ColumnFramePreferenceKey.self,
                    value: [interval: geo.frame(in: .named("kanbanCoordinateSpace"))]
                )
            }
        )
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
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ForEach(parsedScratchpadLists) { list in
                            KanbanScratchpadListCardView(
                                list: list,
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        parsedScratchpadLists.removeAll(where: { $0.id == list.id })
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
        .frame(width: 210)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03))
        )
    }
    
    // MARK: - Column Frame Hit Testing
    
    private func updateHoveredColumn(at location: CGPoint) {
        for (interval, frame) in columnFrames {
            if frame.contains(location) {
                if hoveredColumn != interval {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        hoveredColumn = interval
                    }
                }
                return
            }
        }
        if hoveredColumn != nil {
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredColumn = nil
            }
        }
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

// MARK: - PreferenceKey for Column Frames

struct ColumnFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Kanban Subviews

struct KanbanTaskCardView: View {
    let task: ImportedTask
    let isDragging: Bool
    let onDelete: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isCardHovered = false
    @State private var isXHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(task.text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
                
                // Small hover-accentuated X button
                Button(action: {
                    onDelete()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(isXHovered ? .primary : .secondary.opacity(0.35))
                        .padding(3)
                        .background(
                            Circle()
                                .fill(isXHovered ? Color.primary.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .opacity(isCardHovered || isXHovered ? 1.0 : 0.2)
                .onHover { isXHovered = $0 }
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
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
                .shadow(color: Color.black.opacity(isCardHovered ? 0.08 : 0.03), radius: isCardHovered ? 4 : 2, y: 1)
        )
        .opacity(isDragging ? 0.2 : 1.0)
        .scaleEffect(isCardHovered && !isDragging ? 1.015 : 1.0)
        .onHover { isCardHovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("kanbanCoordinateSpace"))
                .onChanged { value in
                    onDragChanged(value.location)
                }
                .onEnded { _ in
                    onDragEnded()
                }
        )
    }
    
    private func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        return df.string(from: date)
    }
}

struct FloatingKanbanTaskCardView: View {
    let task: ImportedTask
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
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
        .padding(9)
        .frame(width: 165, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.22) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 14, y: 7)
        )
        .rotationEffect(.degrees(2.0))
        .scaleEffect(1.05)
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
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var isXHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(list.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(list.items.count)")
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                
                // Small hover-accentuated X button to remove list
                Button(action: {
                    onDelete()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(isXHovered ? .primary : .secondary.opacity(0.35))
                        .padding(3)
                        .background(
                            Circle()
                                .fill(isXHovered ? Color.primary.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .opacity(isHovered || isXHovered ? 1.0 : 0.2)
                .onHover { isXHovered = $0 }
            }
            
            ForEach(list.items.prefix(3), id: \.id) { item in
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
            
            if list.items.count > 3 {
                Text("+ \(list.items.count - 3) \("more items".localized)")
                    .font(.system(size: 9, weight: .light))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.leading, 8)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
                .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 4 : 2, y: 1)
        )
        .onHover { isHovered = $0 }
    }
}
