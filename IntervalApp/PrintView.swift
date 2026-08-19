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
    let iconSize: CGFloat
    let lineSpacing: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            Text(title.uppercased())
                .font(.system(size: titleSize, weight: .semibold))
                .tracking(2.0)
                .foregroundColor(Color.black.opacity(0.65))
                .padding(.bottom, 2)
            
            if tasks.isEmpty {
                Text("—")
                    .font(.system(size: taskSize, weight: .light))
                    .foregroundColor(Color.black.opacity(0.2))
                    .padding(.top, 2)
            } else {
                VStack(alignment: .leading, spacing: lineSpacing) {
                    ForEach(tasks) { task in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle")
                                .font(.system(size: iconSize))
                                .foregroundColor(Color.black.opacity(0.35))
                                .padding(.top, (taskSize - iconSize) / 2 + 1)
                            
                            Text(task.text)
                                .font(.system(size: taskSize, weight: .light))
                                .foregroundColor(Color.black)
                                .lineSpacing(2)
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
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()
    
    private func activeTasks(for interval: String) -> [TaskItem] {
        tasks.filter { $0.intervalType == interval && $0.deletedAt == nil && !$0.completed }
            .sorted { $0.order < $1.order }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: 1. Header (Title & Date)
            HStack(alignment: .lastTextBaseline) {
                Text("INTERVAL")
                    .font(.system(size: 16, weight: .light))
                    .tracking(3.5)
                    .foregroundColor(Color.black)
                
                Spacer()
                
                Text(Self.dateFormatter.string(from: Date()))
                    .font(.system(size: 9, weight: .light))
                    .foregroundColor(Color.black.opacity(0.5))
            }
            
            // MARK: 2. Habits Bar (Under Header)
            let activeHabits = habits.filter { $0.deletedAt == nil && $0.isScheduledForTodayOrOverdue() }
            if !activeHabits.isEmpty {
                HStack(spacing: 6) {
                    ForEach(activeHabits) { habit in
                        HStack(spacing: 4) {
                            Image(systemName: habit.isCompletedCurrentPeriod ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 7.5))
                                .foregroundColor(Color.black.opacity(habit.isCompletedCurrentPeriod ? 0.9 : 0.4))
                            
                            Text(habit.text)
                                .font(.system(size: 8.5, weight: .light))
                                .foregroundColor(Color.black)
                                .strikethrough(habit.isCompletedCurrentPeriod)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule().fill(Color.black.opacity(0.03))
                        )
                        .overlay(
                            Capsule().stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                        )
                    }
                }
                .padding(.bottom, 2)
            }
            
            // Subtle Divider under Header & Habits
            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 0.5)
            
            // MARK: 3. Recursive 50% Subdivision Layout
            HStack(spacing: 0) {
                // LEFT 50%: 1 HOUR (Largest block & typography)
                PrintIntervalBlock(
                    title: "1 Hour",
                    tasks: activeTasks(for: "1 Hour"),
                    titleSize: 11,
                    taskSize: 13,
                    iconSize: 9,
                    lineSpacing: 8
                )
                .padding(.trailing, 16)
                
                // Vertical Divider
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 0.5)
                
                // RIGHT 50%: 1 DAY (Top) + [1 WEEK & 1 MONTH & 1 YEAR] (Bottom)
                VStack(spacing: 0) {
                    // TOP 50% OF RIGHT: 1 DAY (Medium block & typography)
                    PrintIntervalBlock(
                        title: "1 Day",
                        tasks: activeTasks(for: "1 Day"),
                        titleSize: 10,
                        taskSize: 11,
                        iconSize: 8,
                        lineSpacing: 6
                    )
                    .padding(.leading, 16)
                    .padding(.bottom, 12)
                    
                    // Horizontal Divider
                    Rectangle()
                        .fill(Color.black.opacity(0.12))
                        .frame(height: 0.5)
                    
                    // BOTTOM 50% OF RIGHT: 1 WEEK (Left) + [1 MONTH & 1 YEAR] (Right)
                    HStack(spacing: 0) {
                        // 1 WEEK
                        PrintIntervalBlock(
                            title: "1 Week",
                            tasks: activeTasks(for: "1 Week"),
                            titleSize: 9,
                            taskSize: 9.5,
                            iconSize: 7,
                            lineSpacing: 5
                        )
                        .padding(.leading, 16)
                        .padding(.trailing, 12)
                        .padding(.top, 12)
                        
                        // Vertical Divider
                        Rectangle()
                            .fill(Color.black.opacity(0.12))
                            .frame(width: 0.5)
                        
                        // 1 MONTH (Top) & 1 YEAR (Bottom)
                        VStack(spacing: 0) {
                            // 1 MONTH
                            PrintIntervalBlock(
                                title: "1 Month",
                                tasks: activeTasks(for: "1 Month"),
                                titleSize: 8.5,
                                taskSize: 8.5,
                                iconSize: 6.5,
                                lineSpacing: 4
                            )
                            .padding(.leading, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                            
                            // Horizontal Divider
                            Rectangle()
                                .fill(Color.black.opacity(0.12))
                                .frame(height: 0.5)
                            
                            // 1 YEAR
                            PrintIntervalBlock(
                                title: "1 Year",
                                tasks: activeTasks(for: "1 Year"),
                                titleSize: 8.5,
                                taskSize: 8.5,
                                iconSize: 6.5,
                                lineSpacing: 4
                            )
                            .padding(.leading, 12)
                            .padding(.top, 8)
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
