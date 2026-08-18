import Foundation
import UserNotifications
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
public final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()
    
    @Published public var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task {
            await refreshAuthorizationStatus()
        }
    }
    
    public func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.authorizationStatus = settings.authorizationStatus
    }
    
    @discardableResult
    public func requestAuthorization() async -> Bool {
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
    
    public func openSystemNotificationSettings() {
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
    
    // MARK: - Migration Notifications
    
    public func sendMigrationNotification(for migration: Migration) {
        let isEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        guard isEnabled, authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        
        let content = UNMutableNotificationContent()
        
        if migration.dest == HabitTaskLink.hourInterval {
            content.title = "Hour Migration Ready".localized
            content.body = "Time to choose your tasks for the upcoming hour.".localized
        } else if migration.source == "1 Week" && migration.dest == "1 Day" {
            content.title = "Day Migration Ready".localized
            content.body = "Plan your tasks for today.".localized
        } else if migration.source == "1 Month" && migration.dest == "1 Week" {
            content.title = "Week Migration Ready".localized
            content.body = "Review and organize your week.".localized
        } else if migration.source == "1 Year" && migration.dest == "1 Month" {
            content.title = "Month Migration Ready".localized
            content.body = "Set your priorities for the new month.".localized
        } else if migration.source == "1 Year" && migration.dest == "1 Year" {
            content.title = "Year Migration Ready".localized
            content.body = "Review your year and set new goals.".localized
        } else {
            content.title = "Migration Ready".localized
            content.body = "New interval migration is available.".localized
        }
        
        content.sound = .default
        content.userInfo = ["type": "migration", "source": migration.source, "dest": migration.dest]
        
        let request = UNNotificationRequest(
            identifier: "migration_\(Date().timeIntervalSince1970)",
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
    
    public func scheduleUpcomingBoundaryNotifications() {
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
            content.title = "Hour Migration Ready".localized
            content.body = "Time to choose your tasks for the upcoming hour.".localized
            content.sound = .default
            content.userInfo = ["type": "migration", "source": "1 Day", "dest": "1 Hour"]
            
            let request = UNNotificationRequest(identifier: "scheduled_next_hour", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
        
        // 2. Next Midnight (Day) trigger
        if let nextDay = cal.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) {
            let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nextDay)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let content = UNMutableNotificationContent()
            content.title = "Day Migration Ready".localized
            content.body = "Plan your tasks for today.".localized
            content.sound = .default
            content.userInfo = ["type": "migration", "source": "1 Week", "dest": "1 Day"]
            
            let request = UNNotificationRequest(identifier: "scheduled_next_day", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    public nonisolated func userNotificationCenter(
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
    
    public nonisolated func userNotificationCenter(
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
