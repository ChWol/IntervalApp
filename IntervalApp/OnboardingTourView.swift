#if !os(watchOS)
import SwiftUI

enum OnboardingPage: Equatable {
    case welcome
    case tour
}

enum OnboardingDestination: Equatable {
    case intervals
    case scratchpad
    case habitStats
    case settings
}

enum OnboardingEligibility {
    static func shouldWelcome(
        initialPullComplete: Bool,
        pendingEmail: String?,
        signedInEmail: String?,
        accountIsEmpty: Bool,
        alreadyCompleted: Bool
    ) -> Bool {
        guard initialPullComplete, accountIsEmpty, !alreadyCompleted,
              let pendingEmail, let signedInEmail else { return false }
        return pendingEmail == signedInEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct OnboardingStep {
    let title: String
    let message: String
    let target: String
    let destination: OnboardingDestination

    var intervalScrollTarget: String? {
        switch target {
        case "1 Hour", "hourAdd", "hourComplete", "hourFocus": return "onboarding-1 Hour"
        case "1 Day", "1 Week", "1 Month", "1 Year": return "onboarding-\(target)"
        case "habitAdd": return "onboarding-habits"
        default: return nil
        }
    }

    static let all: [OnboardingStep] = [
        .init(title: "A home for every time horizon", message: "Your plan runs from 1 Hour to 1 Year. Put what matters now at the top, and keep longer plans below.", target: "1 Hour", destination: .intervals),
        .init(title: "Add and edit tasks", message: "Use + beside an interval to add a task. Click or tap a task to edit its text whenever plans change.", target: "hourAdd", destination: .intervals),
        .init(title: "Move plans as they change", message: "Drag tasks within an interval to reorder them, or into another interval to change when you plan to do them.", target: "1 Day", destination: .intervals),
        .init(title: "Keep the longer view", message: "1 Week, 1 Month, and 1 Year give larger goals a home. Move an idea closer as it becomes something you can act on.", target: "1 Year", destination: .intervals),
        .init(title: "Finish or remove a task", message: "Tick the dash when a task is done. Use × to move it to Recently Deleted. Below your lists you can restore a task, or clear it permanently.", target: "hourComplete", destination: .intervals),
        .init(title: "Focus on just one thing", message: "The viewfinder beside a task opens Deep Focus. The rest of the app fades away until you close it or press Escape.", target: "hourFocus", destination: .intervals),
        .init(title: "Plan each new interval", message: "At an hour, day, week, month, or year boundary, Interval asks which tasks should move into your next focus. Select what you want, or press Escape to skip. Unselected tasks stay where they are.", target: "1 Hour", destination: .intervals),
        .init(title: "Make room for habits", message: "Add a daily or weekly habit here. Tick it when done, postpone it for today, or drag it into 1 Hour when you want to focus on it.", target: "habitAdd", destination: .intervals),
        .init(title: "See your rhythm", message: "Habit Statistics shows streaks, yearly completions, and a calendar for each habit.", target: "habitStats", destination: .habitStats),
        .init(title: "Keep flexible lists", message: "Scratchpad is for notes and lists that do not need a time horizon. Create lists and items, then move an item into your main plan when it becomes actionable.", target: "scratchpadNewList", destination: .scratchpad),
        .init(title: "Share a list", message: "Open a Scratchpad list and use its people button to share it. Shared lists stay separate from your interval tasks.", target: "scratchpadShare", destination: .scratchpad),
        .init(title: "Find anything quickly", message: searchMessage, target: "search", destination: .intervals),
        .init(title: "Make Interval yours", message: "Settings holds language, habits, sound, notifications, and the start of your day and week. Your account also syncs your plans across signed-in devices.", target: "settings", destination: .settings),
        .init(title: "Import whenever you like", message: "You can import from other apps later in Settings → Data & Import. You can also export a JSON backup here.", target: "settingsImport", destination: .settings),
        .init(title: "Stay on track anywhere", message: platformExtrasMessage, target: platformTarget, destination: .settings),
        .init(title: "You're ready", message: "Start with one thing you want to do this hour. You can replay this tour any time from Settings.", target: "1 Hour", destination: .intervals)
    ]

    private static var platformExtrasMessage: String {
        #if os(macOS)
        return "Keep your 1 Hour tasks in the menu bar, choose whether Interval launches at login, and print or save your plan with ⌘P."
        #else
        return "Use Interval on your phone with widgets and, if enabled in Settings, Dynamic Island and Live Activities for your current hour."
        #endif
    }

    private static var platformTarget: String {
        #if os(macOS)
        return "settingsMenuBar"
        #else
        return "settingsLiveActivities"
        #endif
    }

    private static var searchMessage: String {
        #if os(macOS)
        return "Search looks across intervals, habits, and lists. Press ⌘F or ⌘K to open it quickly."
        #else
        return "Search looks across intervals, habits, and lists. Tap the magnifying glass to find what you need."
        #endif
    }
}

struct OnboardingTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func onboardingTarget(_ id: String) -> some View {
        anchorPreference(key: OnboardingTargetPreferenceKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }
}

struct OnboardingWelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onImport: () -> Void
    let onStartFresh: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.78 : 0.58).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("WELCOME TO INTERVAL".localized)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onSkip) {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(InteractivePlainButtonStyle())
                    .accessibilityLabel("Skip onboarding".localized)
                }

                Text("Make space for what matters now.".localized)
                    .font(.system(size: 27, weight: .light, design: .rounded))

                Text("Import your existing tasks from TickTick, Microsoft To Do, Todoist or Apple Reminders, or start fresh.".localized)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    Button(action: onImport) {
                        Label("Import Tasks".localized, systemImage: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 17)
                            .padding(.vertical, 10)
                            .foregroundStyle(colorScheme == .dark ? .black : .white)
                            .background(Capsule().fill(Color.primary))
                    }
                    .buttonStyle(InteractivePlainButtonStyle())

                    Button("Start Fresh".localized, action: onStartFresh)
                        .font(.system(size: 13, weight: .light))
                        .buttonStyle(InteractivePlainButtonStyle())
                }

                Text("You can import later in Settings → Data & Import.".localized)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 470)
            .background(RoundedRectangle(cornerRadius: 18).fill(colorScheme == .dark ? Color(white: 0.11) : .white))
            .shadow(color: .black.opacity(0.2), radius: 24)
            .padding(20)
        }
        #if os(macOS)
        .onExitCommand(perform: onSkip)
        #endif
    }
}

struct OnboardingSpotlightView: View {
    @Environment(\.colorScheme) private var colorScheme
    let step: OnboardingStep
    let index: Int
    let total: Int
    let targetFrame: CGRect?
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let frame = targetFrame.flatMap { candidate -> CGRect? in
                let visible = candidate.intersection(bounds)
                guard !visible.isNull,
                      visible.width > 8,
                      visible.height > 6,
                      visible.height >= candidate.height * 0.75 else { return nil }
                return visible.insetBy(dx: -8, dy: -7)
            }

            ZStack {
                Path { path in
                    path.addRect(bounds)
                    if let frame {
                        path.addRoundedRect(in: frame, cornerSize: CGSize(width: 12, height: 12))
                    }
                }
                .fill(Color.black.opacity(colorScheme == .dark ? 0.78 : 0.62), style: FillStyle(eoFill: true))

                if let frame {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }

                card
                    .frame(width: min(390, max(280, geometry.size.width - 32)))
                    .position(
                        x: geometry.size.width / 2,
                        y: cardCenterY(frame: frame, height: geometry.size.height)
                    )
            }
        }
        #if os(macOS)
        .onExitCommand(perform: onSkip)
        #endif
    }

    private func cardCenterY(frame: CGRect?, height: CGFloat) -> CGFloat {
        guard let frame else { return height / 2 }
        let below = frame.midY < height / 2
        let proposed = below ? frame.maxY + 145 : frame.minY - 145
        return min(max(proposed, 155), max(155, height - 155))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("GETTING STARTED".localized)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.6)
                Spacer()
                Text("\(index + 1) / \(total)")
                    .font(.system(size: 10, weight: .light, design: .monospaced))
            }
            .foregroundStyle(.secondary)

            Text(step.title.localized)
                .font(.system(size: 23, weight: .light, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            Text(step.message.localized)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if step.title == "Plan each new interval" {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle")
                    Text("Choose a task".localized)
                    Spacer()
                    Text("Migrate  /  Skip".localized)
                }
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(.secondary)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                .accessibilityLabel("Example transition: choose a task, migrate, or skip".localized)
            }

            HStack {
                Button("Skip tour".localized, action: onSkip)
                    .foregroundStyle(.secondary)
                Spacer()
                if index > 0 {
                    Button("Back".localized, action: onBack)
                }
                Button(index == total - 1 ? "Finish".localized : "Next".localized, action: onNext)
                    .fontWeight(.medium)
            }
            .font(.system(size: 12))
            .buttonStyle(InteractivePlainButtonStyle())
            .padding(.top, 5)
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color(white: 0.12) : .white))
        .shadow(color: .black.opacity(0.24), radius: 22)
    }
}
#endif
