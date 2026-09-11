import SwiftUI
import WidgetKit
import ActivityKit

private let intervalInk = Color(red: 0.12, green: 0.12, blue: 0.12)

struct IntervalWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> IntervalWidgetEntry { .init(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (IntervalWidgetEntry) -> Void) { completion(.init(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<IntervalWidgetEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: Date())], policy: .after(Date().addingTimeInterval(900))))
    }
}

struct IntervalWidgetEntry: TimelineEntry { let date: Date }

struct IntervalWidgetView: View {
    let entry: IntervalWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INTERVAL").font(.caption2).tracking(2).foregroundStyle(.secondary)
            Text("1 HOUR").font(.system(size: 21, weight: .light, design: .rounded))
            Spacer()
            Text("Open your next task").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .containerBackground(for: .widget) { intervalInk }
        .widgetURL(URL(string: "interval://main"))
    }
}

struct IntervalHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "IntervalHomeWidget", provider: IntervalWidgetProvider()) { entry in
            IntervalWidgetView(entry: entry)
        }
        .configurationDisplayName("Interval")
        .description("A quiet shortcut to your current hour.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
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
