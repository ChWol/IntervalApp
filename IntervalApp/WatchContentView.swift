import SwiftUI
import SwiftData
import Combine
#if os(watchOS)
import WatchKit
#endif

public enum WatchTab: String, CaseIterable, Identifiable {
    case hour = "1 Hour"
    case day = "1 Day"
    case habits = "Habits"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hour: return "1 STUNDE".localized
        case .day: return "1 TAG".localized
        case .habits: return "GEWOHNHEITEN".localized
        }
    }

    public var shortName: String {
        switch self {
        case .hour: return "1H"
        case .day: return "1D"
        case .habits: return "HABITS"
        }
    }
}

public struct WatchContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: WatchTab = .hour
    @State private var now: Date = Date()
    
    // Timer to update countdown every 30 seconds
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Segment Bar
                HStack(spacing: 6) {
                    ForEach(WatchTab.allCases) { tab in
                        Button(action: {
                            #if os(watchOS)
                            WKInterfaceDevice.current().play(.click)
                            #endif
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        }) {
                            Text(tab.shortName)
                                .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary.opacity(0.6))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? Color.white.opacity(0.18) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 6)

                // Active View Content
                switch selectedTab {
                case .hour:
                    WatchTaskListView(intervalType: "1 Hour", headerTitle: "1 STUNDE".localized, remainingText: timeRemainingInHour(from: now))
                case .day:
                    WatchTaskListView(intervalType: "1 Day", headerTitle: "1 TAG".localized, remainingText: timeRemainingInDay(from: now))
                case .habits:
                    WatchHabitsListView()
                }
            }
            .background(Color.black.ignoresSafeArea())
            .onReceive(timer) { newDate in
                now = newDate
            }
        }
    }

    private func timeRemainingInHour(from date: Date) -> String {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let remaining = max(0, 60 - minute)
        return "\(remaining)m"
    }

    private func timeRemainingInDay(from date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let remaining = max(0, 24 - hour)
        return "\(remaining)h"
    }
}
