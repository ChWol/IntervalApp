import Foundation
import UserNotifications
import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    enum Identifier {
        static let hourlyTransition = "interval_transition_hourly"
        static let dailyTransition = "interval_transition_daily"
        static let generalTransition = "interval_transition_general"
        static let legacyIds = ["scheduled_next_hour", "scheduled_next_day"]
    }
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        purgeLegacyNotifications()
        Task {
            await refreshAuthorizationStatus()
        }
    }
    
    private func purgeLegacyNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Identifier.legacyIds)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Identifier.legacyIds)
    }
    
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.authorizationStatus = settings.authorizationStatus
    }
    
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if granted {
                scheduleUpcomingBoundaryNotifications()
            }
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }
    
    func openSystemNotificationSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            if NSWorkspace.shared.open(url) { return }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            if NSWorkspace.shared.open(url) { return }
        }
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
        #elseif os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
    
    // MARK: - Migration / Interval Notifications
    
    private var lastSentMigrationKey: String = ""
    private var lastSentMigrationTime: Date = .distantPast
    
    func sendMigrationNotification(for migration: Migration) {
        let isEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        guard isEnabled, authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        
        let hourStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let dedupeKey = "\(migration.source)_\(migration.dest)_\(hourStr)"
        if lastSentMigrationKey == dedupeKey && Date().timeIntervalSince(lastSentMigrationTime) < 300 {
            return // Prevent duplicate notifications within the same transition cycle
        }
        lastSentMigrationKey = dedupeKey
        lastSentMigrationTime = Date()
        
        let identifier: String
        let title: String
        let body: String
        
        if migration.dest == HabitTaskLink.hourInterval {
            identifier = Identifier.hourlyTransition
            title = "A new hour begins".localized
            body = "Time to choose your focus for the upcoming hour.".localized
        } else if migration.source == "1 Week" && migration.dest == "1 Day" {
            identifier = Identifier.dailyTransition
            title = "A new day begins".localized
            body = "What would you like to focus on today?".localized
        } else if migration.source == "1 Month" && migration.dest == "1 Week" {
            identifier = Identifier.generalTransition
            title = "A new week begins".localized
            body = "Time to set your priorities for the week.".localized
        } else if migration.source == "1 Year" && migration.dest == "1 Month" {
            identifier = Identifier.generalTransition
            title = "A new month begins".localized
            body = "Time to review your monthly goals.".localized
        } else if migration.source == "1 Year" && migration.dest == "1 Year" {
            identifier = Identifier.generalTransition
            title = "A new year begins".localized
            body = "Reflect on the past year and set new goals.".localized
        } else {
            identifier = Identifier.generalTransition
            title = "A new interval begins".localized
            body = "Time to review and plan your tasks.".localized
        }
        
        // Remove existing pending and delivered notifications for this identifier to prevent duplicates
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["type": "migration", "source": migration.source, "dest": migration.dest]
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationManager] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Schedule Upcoming Boundaries (for Background Alerts)
    
    func scheduleUpcomingBoundaryNotifications() {
        let isEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        guard isEnabled, authorizationStatus == .authorized || authorizationStatus == .provisional else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }
        
        purgeLegacyNotifications()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Identifier.hourlyTransition, Identifier.dailyTransition])
        
        let cal = Calendar.current
        let now = Date()
        
        // 1. Next Hour trigger
        if let nextHour = cal.nextDate(after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) {
            let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nextHour)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let content = UNMutableNotificationContent()
            content.title = "A new hour begins".localized
            content.body = "Time to choose your focus for the upcoming hour.".localized
            content.sound = .default
            content.userInfo = ["type": "migration", "source": "1 Day", "dest": "1 Hour"]
            
            let request = UNNotificationRequest(identifier: Identifier.hourlyTransition, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
        
        // 2. Next Day trigger (at configured dayStartHour / dayStartMinute)
        let startHour = UserDefaults.standard.object(forKey: "dayStartHour") != nil ? UserDefaults.standard.integer(forKey: "dayStartHour") : 6
        let startMinute = UserDefaults.standard.integer(forKey: "dayStartMinute")
        
        if let nextDay = cal.nextDate(after: now, matching: DateComponents(hour: startHour, minute: startMinute, second: 0), matchingPolicy: .nextTime) {
            let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nextDay)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let content = UNMutableNotificationContent()
            content.title = "A new day begins".localized
            content.body = "What would you like to focus on today?".localized
            content.sound = .default
            content.userInfo = ["type": "migration", "source": "1 Week", "dest": "1 Day"]
            
            let request = UNNotificationRequest(identifier: Identifier.dailyTransition, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // If the app is active and currently showing the migration modal, suppress redundant system banner & sound
        Task { @MainActor in
            if MigrationManager.shared.currentMigration != nil {
                completionHandler([])
            } else {
                #if os(macOS)
                completionHandler([.banner, .sound])
                #else
                completionHandler([.banner, .sound, .badge])
                #endif
            }
        }
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            MigrationManager.shared.checkMigrations()
        }
        completionHandler()
    }
}
