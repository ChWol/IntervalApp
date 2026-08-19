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
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INTERVAL")
                        .font(.system(size: 16, weight: .light))
                        .tracking(3.0)
                    Text(Self.dateFormatter.string(from: Date()))
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 8)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(.black.opacity(0.15)),
                alignment: .bottom
            )
            
            // Habits Bar (if any)
            let activeHabits = habits.filter { $0.deletedAt == nil && $0.isScheduledForTodayOrOverdue() }
            if !activeHabits.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HABITS")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(activeHabits) { habit in
                            HStack(spacing: 4) {
                                Image(systemName: habit.isCompletedCurrentPeriod ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 8))
                                Text(habit.text)
                                    .font(.system(size: 9, weight: .light))
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
                .padding(.bottom, 6)
            }
            
            // Interval Columns Grid
            let columns = ["1 Hour", "1 Day", "1 Week", "1 Month", "1 Year"]
            HStack(alignment: .top, spacing: 16) {
                ForEach(columns, id: \.self) { col in
                    let colTasks = tasks.filter { $0.intervalType == col && $0.deletedAt == nil && !$0.completed }
                        .sorted { $0.order < $1.order }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(col.uppercased())
                            .font(.system(size: 9, weight: .medium))
                            .tracking(1.5)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                            .overlay(
                                Rectangle().frame(height: 0.5).foregroundColor(.black.opacity(0.15)),
                                alignment: .bottom
                            )
                        
                        if colTasks.isEmpty {
                            Text("—")
                                .font(.system(size: 10, weight: .light))
                                .foregroundColor(.secondary.opacity(0.5))
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(colTasks) { task in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "circle")
                                            .font(.system(size: 7))
                                            .padding(.top, 2)
                                            .foregroundColor(.secondary)
                                        Text(task.text)
                                            .font(.system(size: 10, weight: .light))
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            
            Spacer(minLength: 20)
        }
        .padding(32)
        .frame(width: 760, alignment: .topLeading)
        .background(Color.white)
        .foregroundColor(Color.black)
    }
}

// MARK: - Print Manager

@MainActor
final class PrintManager {
    static func printIntervals(context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<HabitItem>())) ?? []
        
        let printView = PrintableIntervalsView(tasks: tasks, habits: habits)
        let hostingView = NSHostingView(rootView: printView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 760, height: 500)
        hostingView.layoutSubtreeIfNeeded()
        
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 842, height: 595) // A4 landscape default or standard letter
        printInfo.orientation = .landscape
        printInfo.topMargin = 20
        printInfo.bottomMargin = 20
        printInfo.leftMargin = 20
        printInfo.rightMargin = 20
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        
        let printOperation = NSPrintOperation(view: hostingView, printInfo: printInfo)
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
