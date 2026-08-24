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
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task {
            await refreshAuthorizationStatus()
        }
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
        
        let content = UNMutableNotificationContent()
        
        if migration.dest == HabitTaskLink.hourInterval {
            content.title = "A new hour begins".localized
            content.body = "Time to choose your focus for the upcoming hour.".localized
        } else if migration.source == "1 Week" && migration.dest == "1 Day" {
            content.title = "A new day begins".localized
            content.body = "What would you like to focus on today?".localized
        } else if migration.source == "1 Month" && migration.dest == "1 Week" {
            content.title = "A new week begins".localized
            content.body = "Time to set your priorities for the week.".localized
        } else if migration.source == "1 Year" && migration.dest == "1 Month" {
            content.title = "A new month begins".localized
            content.body = "Time to review your monthly goals.".localized
        } else if migration.source == "1 Year" && migration.dest == "1 Year" {
            content.title = "A new year begins".localized
            content.body = "Reflect on the past year and set new goals.".localized
        } else {
            content.title = "A new interval begins".localized
            content.body = "Time to review and plan your tasks.".localized
        }
        
        content.sound = .default
        content.userInfo = ["type": "migration", "source": migration.source, "dest": migration.dest]
        
        let identifier = "interval_migration_\(dedupeKey.replacingOccurrences(of: " ", with: "_"))"
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error.localizedDescription)")
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
        
        // Remove existing scheduled boundary triggers
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["scheduled_next_hour", "scheduled_next_day"])
        
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
            
            let request = UNNotificationRequest(identifier: "scheduled_next_hour", content: content, trigger: trigger)
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
            
            let request = UNNotificationRequest(identifier: "scheduled_next_day", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even if app is foregrounded
        #if os(macOS)
        completionHandler([.banner, .sound])
        #else
        completionHandler([.banner, .sound, .badge])
        #endif
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
