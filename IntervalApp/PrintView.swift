import SwiftUI
import SwiftData
#if os(macOS)
import AppKit

// MARK: - Printable Document View

struct PrintableIntervalsView: View {
    let tasks: [TaskItem]
    let habits: [HabitItem]
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INTERVAL")
                        .font(.system(size: 18, weight: .light))
                        .tracking(3.5)
                        .foregroundColor(Color.black)
                    Text(Self.dateFormatter.string(from: Date()))
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(Color.black.opacity(0.6))
                }
                Spacer()
            }
            .padding(.bottom, 8)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(Color.black.opacity(0.15)),
                alignment: .bottom
            )
            
            // Habits Bar (if any)
            let activeHabits = habits.filter { $0.deletedAt == nil && $0.isScheduledForTodayOrOverdue() }
            if !activeHabits.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HABITS")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(Color.black.opacity(0.55))
                    
                    HStack(spacing: 8) {
                        ForEach(activeHabits) { habit in
                            HStack(spacing: 4) {
                                Image(systemName: habit.isCompletedCurrentPeriod ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.black)
                                Text(habit.text)
                                    .font(.system(size: 9, weight: .light))
                                    .foregroundColor(Color.black)
                                    .strikethrough(habit.isCompletedCurrentPeriod)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .overlay(
                                Capsule().stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                            )
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            
            // Interval Columns Grid
            let columns = ["1 Hour", "1 Day", "1 Week", "1 Month", "1 Year"]
            HStack(alignment: .top, spacing: 14) {
                ForEach(columns, id: \.self) { col in
                    let colTasks = tasks.filter { $0.intervalType == col && $0.deletedAt == nil && !$0.completed }
                        .sorted { $0.order < $1.order }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(col.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(Color.black.opacity(0.55))
                            .padding(.bottom, 2)
                            .overlay(
                                Rectangle().frame(height: 0.5).foregroundColor(Color.black.opacity(0.15)),
                                alignment: .bottom
                            )
                        
                        if colTasks.isEmpty {
                            Text("—")
                                .font(.system(size: 10, weight: .light))
                                .foregroundColor(Color.black.opacity(0.25))
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(colTasks) { task in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "circle")
                                            .font(.system(size: 7))
                                            .padding(.top, 2)
                                            .foregroundColor(Color.black.opacity(0.4))
                                        Text(task.text)
                                            .font(.system(size: 10, weight: .light))
                                            .foregroundColor(Color.black)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            
            Spacer(minLength: 10)
        }
        .padding(32)
        .frame(width: 800, height: 550, alignment: .topLeading)
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
        
        // Render view using ImageRenderer to ensure 100% rasterized content in print preview
        let renderer = ImageRenderer(content: printView)
        renderer.scale = 2.0 // High-DPI crisp print quality
        
        guard let nsImage = renderer.nsImage else {
            print("Failed to render print image")
            return
        }
        
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 800, height: 550))
        imageView.image = nsImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 842, height: 595) // A4 / Letter landscape
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
