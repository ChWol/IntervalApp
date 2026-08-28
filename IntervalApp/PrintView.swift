#if !os(watchOS)
import SwiftUI
import SwiftData
#if os(macOS)
import AppKit

// MARK: - Single Interval Print Block

private struct PrintIntervalBlock: View {
    let title: String
    let tasks: [TaskItem]
    let titleSize: CGFloat
    let taskSize: CGFloat
    let lineSpacing: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header (Localized Title)
            Text(title.localized.uppercased())
                .font(.system(size: titleSize, weight: .medium))
                .tracking(1.8)
                .foregroundColor(Color.black.opacity(0.6))
                .padding(.bottom, 2)
            
            if tasks.isEmpty {
                Text("—")
                    .font(.system(size: taskSize, weight: .light))
                    .foregroundColor(Color.black.opacity(0.18))
                    .padding(.top, 1)
            } else {
                VStack(alignment: .leading, spacing: lineSpacing) {
                    ForEach(tasks) { task in
                        HStack(alignment: .top, spacing: max(4, taskSize * 0.35)) {
                            // Interval's signature dash marker
                            Text("–")
                                .font(.system(size: taskSize * 0.85, weight: .light))
                                .foregroundColor(Color.black.opacity(0.4))
                                .frame(width: max(8, taskSize * 0.6), alignment: .center)
                            
                            Text(task.text)
                                .font(.system(size: taskSize, weight: .light))
                                .foregroundColor(Color.black)
                                .lineSpacing(1.5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Printable Document View (Recursive 50% Subdivision Layout)

struct PrintableIntervalsView: View {
    let tasks: [TaskItem]
    let habits: [HabitItem]
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        return formatter.string(from: Date())
    }
    
    private func activeTasks(for interval: String) -> [TaskItem] {
        tasks.filter { $0.intervalType == interval && $0.deletedAt == nil && !$0.completed }
            .sorted { $0.order < $1.order }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: 1. Header (Logo, Title & Localized Date)
            HStack(alignment: .center, spacing: 8) {
                // Subtle App Logo
                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5))
                }
                
                Text("INTERVAL")
                    .font(.system(size: 14, weight: .light))
                    .tracking(3.5)
                    .foregroundColor(Color.black)
                
                Spacer()
                
                Text(formattedDate)
                    .font(.system(size: 9, weight: .light))
                    .foregroundColor(Color.black.opacity(0.45))
            }
            
            // MARK: 2. Quiet Habits Bar (Single thin line separated by /)
            let activeHabits = habits.filter { $0.deletedAt == nil && $0.isScheduledForTodayOrOverdue() }
            let habitTitles = activeHabits.map { $0.text }
            if !habitTitles.isEmpty {
                Text(habitTitles.joined(separator: "   /   "))
                    .font(.system(size: 9, weight: .light))
                    .foregroundColor(Color.black.opacity(0.4))
                    .lineLimit(1)
                    .padding(.top, -3)
                    .padding(.bottom, 2)
            }
            
            // Subtle Hairline Divider under Header & Habits
            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(height: 0.5)
            
            // MARK: 3. Recursive 50% Subdivision Layout with App Font-Hierarchy Ratios
            HStack(spacing: 0) {
                // LEFT 50%: 1 HOUR (20pt typography - large & spacious)
                PrintIntervalBlock(
                    title: "1 Hour",
                    tasks: activeTasks(for: "1 Hour"),
                    titleSize: 11,
                    taskSize: 20,
                    lineSpacing: 7
                )
                .padding(.trailing, 16)
                
                // Vertical Divider
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 0.5)
                
                // RIGHT 50%: 1 DAY (Top) + [1 WEEK & 1 MONTH & 1 YEAR] (Bottom)
                VStack(spacing: 0) {
                    // TOP 50% OF RIGHT: 1 DAY (13.5pt typography)
                    PrintIntervalBlock(
                        title: "1 Day",
                        tasks: activeTasks(for: "1 Day"),
                        titleSize: 10,
                        taskSize: 13.5,
                        lineSpacing: 5.5
                    )
                    .padding(.leading, 16)
                    .padding(.bottom, 10)
                    
                    // Horizontal Divider
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 0.5)
                    
                    // BOTTOM 50% OF RIGHT: 1 WEEK (Left) + [1 MONTH & 1 YEAR] (Right)
                    HStack(spacing: 0) {
                        // 1 WEEK (9.2pt typography)
                        PrintIntervalBlock(
                            title: "1 Week",
                            tasks: activeTasks(for: "1 Week"),
                            titleSize: 8.5,
                            taskSize: 9.2,
                            lineSpacing: 4
                        )
                        .padding(.leading, 16)
                        .padding(.trailing, 12)
                        .padding(.top, 10)
                        
                        // Vertical Divider
                        Rectangle()
                            .fill(Color.black.opacity(0.1))
                            .frame(width: 0.5)
                        
                        // 1 MONTH (Top) & 1 YEAR (Bottom)
                        VStack(spacing: 0) {
                            // 1 MONTH (6.8pt typography)
                            PrintIntervalBlock(
                                title: "1 Month",
                                tasks: activeTasks(for: "1 Month"),
                                titleSize: 7.5,
                                taskSize: 6.8,
                                lineSpacing: 3
                            )
                            .padding(.leading, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                            
                            // Horizontal Divider
                            Rectangle()
                                .fill(Color.black.opacity(0.1))
                                .frame(height: 0.5)
                            
                            // 1 YEAR (5.2pt typography)
                            PrintIntervalBlock(
                                title: "1 Year",
                                tasks: activeTasks(for: "1 Year"),
                                titleSize: 7.0,
                                taskSize: 5.2,
                                lineSpacing: 2.5
                            )
                            .padding(.leading, 12)
                            .padding(.top, 6)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(28)
        .frame(width: 800, height: 530, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Print Manager

@MainActor
final class PrintManager {
    static func printIntervals(context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<HabitItem>())) ?? []
        
        let printView = PrintableIntervalsView(tasks: tasks, habits: habits)
        
        // Render view using ImageRenderer to ensure 100% crisp rasterized vector quality
        let renderer = ImageRenderer(content: printView)
        renderer.scale = 3.0 // Ultra High-DPI crisp print resolution
        
        guard let nsImage = renderer.nsImage else {
            print("Failed to render print image")
            return
        }
        
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 800, height: 530))
        imageView.image = nsImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 842, height: 595) // Standard A4 / Letter Landscape
        printInfo.orientation = .landscape
        printInfo.topMargin = 20
        printInfo.bottomMargin = 20
        printInfo.leftMargin = 20
        printInfo.rightMargin = 20
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        
        let printOperation = NSPrintOperation(view: imageView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        
        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first {
            printOperation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            printOperation.run()
        }
    }
}
#endif

#endif
