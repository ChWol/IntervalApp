import SwiftUI
import WidgetKit
import ActivityKit

private let intervalInk = Color(red: 0.12, green: 0.12, blue: 0.12)
private let intervalPaper = Color(red: 0.94, green: 0.93, blue: 0.89)

struct IntervalWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> IntervalWidgetEntry {
        .init(date: Date(), tasks: [WidgetTaskSnapshot(id: "placeholder", title: "Next small step", order: 0)])
    }
    func getSnapshot(in context: Context, completion: @escaping (IntervalWidgetEntry) -> Void) {
        completion(.init(date: Date(), tasks: WidgetSnapshotStore.read().tasks))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<IntervalWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.read()
        let now = Date()
        let entries = stride(from: 0, through: 60, by: 5).map { minute in
            IntervalWidgetEntry(date: now.addingTimeInterval(TimeInterval(minute * 60)), tasks: snapshot.tasks)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

struct IntervalWidgetEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTaskSnapshot]
}

struct IntervalWidgetView: View {
    let entry: IntervalWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var progress: Double {
        let components = Calendar.current.dateComponents([.minute, .second], from: entry.date)
        return min(1, max(0, Double((components.minute ?? 0) * 60 + (components.second ?? 0)) / 3600))
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                compactLayout
            }
        }
        .containerBackground(for: .widget) { intervalPaper }
        .widgetURL(URL(string: "interval://main"))
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("1 HOUR").font(.caption2.weight(.semibold)).tracking(1.4)
                Spacer()
                Text("\(entry.tasks.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let task = entry.tasks.first {
                Text(task.title).font(.system(size: 17, weight: .medium, design: .rounded)).lineLimit(3)
                Text(entry.tasks.count == 1 ? "next task" : "+ \(entry.tasks.count - 1) more")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("All clear").font(.system(size: 17, weight: .light, design: .rounded))
                Text("Open Interval").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ProgressView(value: progress).tint(.black.opacity(0.75))
        }
        .foregroundStyle(.black)
        .padding(12)
    }

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(.black.opacity(0.12), lineWidth: 5)
                Circle().trim(from: 0, to: progress)
                    .stroke(.black, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("1H").font(.caption.weight(.semibold))
                    Text("\(max(0, 60 - Calendar.current.component(.minute, from: entry.date)))m")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 5) {
                Text("NEXT UP").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                if entry.tasks.isEmpty {
                    Text("All clear").font(.headline.weight(.light))
                } else {
                    ForEach(Array(entry.tasks.prefix(3))) { task in
                        HStack(spacing: 6) {
                            Circle().fill(.black.opacity(0.7)).frame(width: 5, height: 5)
                            Text(task.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        }
                    }
                    if entry.tasks.count > 3 {
                        Text("+\(entry.tasks.count - 3) more").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.black)
        .padding(14)
    }
}

struct IntervalHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "IntervalHomeWidget", provider: IntervalWidgetProvider()) { entry in
            IntervalWidgetView(entry: entry)
        }
        .configurationDisplayName("Interval")
        .description("A quiet shortcut to your current hour.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

@available(iOS 16.1, *)
struct IntervalLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IntervalFocusActivityAttributes.self) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.intervalTitle.uppercased()).font(.caption2).tracking(1.5).foregroundStyle(.secondary)
                    Text(context.state.taskTitles.first ?? "Ready").font(.system(size: 16, weight: .light)).lineLimit(1)
                }
                Spacer()
                Text("\(context.state.remainingMinutes)m").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(16)
            .activityBackgroundTint(intervalInk)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("1H").font(.caption).foregroundStyle(.secondary) }
                DynamicIslandExpandedRegion(.center) { Text(context.state.taskTitles.first ?? "Ready").font(.caption).lineLimit(1) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.remainingMinutes)m").font(.caption2).monospaced() }
                DynamicIslandExpandedRegion(.bottom) { Text("Stay with the next small step.").font(.caption2).foregroundStyle(.secondary) }
            } compactLeading: { Text("1H").font(.caption2) }
            compactTrailing: { Text("\(context.state.remainingMinutes)m").font(.caption2).monospacedDigit() }
            minimal: { Image(systemName: "circle.dotted") }
        }
    }
}

@main
struct IntervalWidgetBundle: WidgetBundle {
    var body: some Widget {
        IntervalHomeWidget()
        if #available(iOS 16.1, *) { IntervalLiveActivityWidget() }
    }
}
