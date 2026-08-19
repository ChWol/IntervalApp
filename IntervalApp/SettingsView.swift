import SwiftUI
import SwiftData
import UserNotifications
#if os(macOS)
import AppKit
import ServiceManagement
#endif

// MARK: - Pointing Hand Cursor Extension

#if os(macOS)
extension View {
    func pointingHandCursor() -> some View {
        self.onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
#else
extension View {
    func pointingHandCursor() -> some View {
        self
    }
}
#endif

// MARK: - Minimalist Custom Toggle

struct MinimalistToggle: View {
    @Binding var isOn: Bool
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isOn.toggle()
            }
        }) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.primary)

                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Color.primary.opacity(colorScheme == .dark ? 0.85 : 0.75) : Color.primary.opacity(0.12))
                        .frame(width: 28, height: 16)

                    Circle()
                        .fill(isOn ? (colorScheme == .dark ? Color.black : Color.white) : Color.gray.opacity(0.5))
                        .frame(width: 12, height: 12)
                        .padding(2)
                        .shadow(color: .black.opacity(isOn ? 0.2 : 0.05), radius: 1, x: 0, y: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

// MARK: - Minimalist Custom Time Picker

struct MinimalistTimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @State private var isPopoverPresented: Bool = false
    @State private var isHovered: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var formattedTime: String {
        String(format: "%02d:%02d", hour, minute)
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                isPopoverPresented.toggle()
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .light))
                    .foregroundColor(isHovered ? .primary : .secondary)
                
                Text(formattedTime)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .light))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
            )
            .overlay(
                Capsule().stroke(Color.primary.opacity(isHovered ? 0.25 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            timePickerPopoverContent
        }
    }
    
    private var timePickerPopoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SELECT TIME".localized)
                .font(.system(size: 9, weight: .light))
                .tracking(1.5)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            
            HStack(spacing: 6) {
                // Hours column
                VStack(alignment: .leading, spacing: 2) {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 1) {
                                ForEach(0..<24, id: \.self) { h in
                                    let isSelected = hour == h
                                    Button(action: {
                                        hour = h
                                    }) {
                                        HStack {
                                            Text(String(format: "%02d", h))
                                                .font(.system(size: 11, weight: isSelected ? .medium : .light))
                                                .foregroundColor(isSelected ? .primary : .secondary)
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 8, weight: .medium))
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08) : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .pointingHandCursor()
                                    .id(h)
                                }
                            }
                        }
                        .frame(width: 58, height: 140)
                        .onAppear {
                            proxy.scrollTo(hour, anchor: .center)
                        }
                    }
                }
                
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1, height: 140)
                
                // Minutes column
                VStack(alignment: .leading, spacing: 2) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 1) {
                            ForEach([0, 15, 30, 45], id: \.self) { m in
                                let isSelected = minute == m
                                Button(action: {
                                    minute = m
                                    isPopoverPresented = false
                                }) {
                                    HStack {
                                        Text(String(format: "%02d", m))
                                            .font(.system(size: 11, weight: isSelected ? .medium : .light))
                                            .foregroundColor(isSelected ? .primary : .secondary)
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8, weight: .medium))
                                                .foregroundColor(.primary)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                        }
                    }
                    .frame(width: 58, height: 140)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 145)
    }
}

// MARK: - Settings Modal Action Type

enum SettingsModalType {
    case signOut
    case deleteAccount
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var locManager = LocalizationManager.shared
    @ObservedObject private var syncManager = SupabaseSyncManager.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showHabits") private var showHabits: Bool = true
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled: Bool = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("dayStartHour") private var dayStartHour: Int = 6
    @AppStorage("dayStartMinute") private var dayStartMinute: Int = 0
    @AppStorage("weekStartDay") private var weekStartDay: String = "Monday"

    @State private var launchAtLogin: Bool = false
    @State private var hoveredLang: AppLanguage? = nil
    @State private var activeModal: SettingsModalType? = nil
    @State private var isSignOutHovered: Bool = false
    @State private var isDeleteHovered: Bool = false
    @State private var isSystemSettingsHovered: Bool = false
    @State private var isImportHovered: Bool = false
    @State private var isExportHovered: Bool = false
    @State private var isEmailHovered: Bool = false
    @State private var isPaypalHovered: Bool = false
    @State private var showImportModal: Bool = false
    @State private var exportSuccess: Bool = false
    
    var onClose: () -> Void

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    // Header: Title
                    Text("SETTINGS".localized)
                        .font(.system(size: 11, weight: .light))
                        .tracking(3.0)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)

                    // MARK: Language
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("LANGUAGE".localized)

                        HStack(spacing: 6) {
                            ForEach(AppLanguage.allCases) { lang in
                                let isSelected = locManager.currentLanguage == lang
                                let isHov = hoveredLang == lang

                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        locManager.currentLanguage = lang
                                    }
                                }) {
                                    HStack(spacing: 5) {
                                        Text(lang.displayName)
                                            .font(.system(size: 12, weight: isSelected ? .medium : .light))
                                            .foregroundColor(isSelected ? .primary : (isHov ? .primary : .secondary))

                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8, weight: .light))
                                                .foregroundColor(.primary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(isSelected
                                            ? Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08)
                                            : (isHov ? Color.primary.opacity(0.04) : Color.clear))
                                    )
                                    .overlay(
                                        Capsule().stroke(
                                            Color.primary.opacity(isSelected ? 0.25 : (isHov ? 0.15 : 0.08)),
                                            lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                .onHover { hoveredLang = $0 ? lang : nil }
                            }
                        }
                    }

                    // MARK: Preferences (Habits, Sounds, Notifications, Autostart & Boundaries)
                    VStack(alignment: .leading, spacing: 14) {
                        sectionLabel("PREFERENCES".localized)

                        // Launch at Login
                        #if os(macOS)
                        MinimalistToggle(
                            isOn: Binding(
                                get: { launchAtLogin },
                                set: { newValue in
                                    launchAtLogin = newValue
                                    if #available(macOS 13.0, *) {
                                        do {
                                            if newValue {
                                                try SMAppService.mainApp.register()
                                            } else {
                                                try SMAppService.mainApp.unregister()
                                            }
                                        } catch {
                                            print("Failed to update Launch at Login: \(error)")
                                        }
                                    }
                                }
                            ),
                            label: "Launch at Login".localized
                        )
                        #endif

                        MinimalistToggle(isOn: $showHabits, label: "Show Habits Bar".localized)
                        MinimalistToggle(isOn: $soundEffectsEnabled, label: "Sound Effects".localized)
                        
                        // Notifications Toggle & Permission handler
                        VStack(alignment: .leading, spacing: 6) {
                            Button(action: {
                                handleNotificationToggle()
                            }) {
                                HStack(spacing: 12) {
                                    Text("Interval Notifications".localized)
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(.primary)

                                    let isToggleActive = notificationsEnabled && (notificationManager.authorizationStatus == .authorized || notificationManager.authorizationStatus == .provisional)
                                    ZStack(alignment: isToggleActive ? .trailing : .leading) {
                                        Capsule()
                                            .fill(isToggleActive ? Color.primary.opacity(colorScheme == .dark ? 0.85 : 0.75) : Color.primary.opacity(0.12))
                                            .frame(width: 28, height: 16)

                                        Circle()
                                            .fill(isToggleActive ? (colorScheme == .dark ? Color.black : Color.white) : Color.gray.opacity(0.5))
                                            .frame(width: 12, height: 12)
                                            .padding(2)
                                            .shadow(color: .black.opacity(isToggleActive ? 0.2 : 0.05), radius: 1, x: 0, y: 0.5)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()

                            if notificationManager.authorizationStatus == .denied {
                                HStack(spacing: 6) {
                                    Text("Notifications are disabled in System Settings.".localized)
                                        .font(.system(size: 10, weight: .light))
                                        .foregroundColor(.red.opacity(0.85))

                                    Button(action: {
                                        notificationManager.openSystemNotificationSettings()
                                    }) {
                                        HStack(spacing: 4) {
                                            Text("Open System Settings".localized)
                                                .font(.system(size: 10, weight: .light))
                                            Image(systemName: "arrow.up.forward.app")
                                                .font(.system(size: 9))
                                        }
                                        .foregroundColor(isSystemSettingsHovered ? .primary : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .pointingHandCursor()
                                    .onHover { isSystemSettingsHovered = $0 }
                                }
                                .padding(.top, 2)
                            }
                        }
                        
                        // Day Start Time
                        HStack(spacing: 12) {
                            Text("Day Starts At".localized)
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.primary)
                            
                            MinimalistTimePicker(hour: $dayStartHour, minute: $dayStartMinute)
                        }
                        .padding(.top, 2)
                        
                        // Week Start Day
                        HStack(spacing: 12) {
                            Text("Week Starts On".localized)
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 6) {
                                ForEach(["Monday", "Sunday"], id: \.self) { day in
                                    let isSelected = weekStartDay == day
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            weekStartDay = day
                                        }
                                    }) {
                                        Text(day.localized)
                                            .font(.system(size: 11, weight: isSelected ? .medium : .light))
                                            .foregroundColor(isSelected ? .primary : .secondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule().fill(isSelected
                                                    ? Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08)
                                                    : Color.clear)
                                            )
                                            .overlay(
                                                Capsule().stroke(
                                                    Color.primary.opacity(isSelected ? 0.25 : 0.08),
                                                    lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .pointingHandCursor()
                                }
                            }
                        }
                    }

                    // MARK: - Data & Import / Export
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("DATA & IMPORT".localized)

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showImportModal = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 11, weight: .light))
                                Text("Import from other apps (TickTick, To Do, Todoist...)".localized)
                                    .font(.system(size: 12, weight: .light))
                            }
                            .foregroundColor(isImportHovered ? .primary : .secondary)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .onHover { isImportHovered = $0 }
                        
                        #if os(macOS)
                        Button(action: {
                            if ExportManager.shared.exportToFile(context: modelContext) {
                                withAnimation { exportSuccess = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    withAnimation { exportSuccess = false }
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: exportSuccess ? "checkmark.circle" : "square.and.arrow.up")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(exportSuccess ? .green : (isExportHovered ? .primary : .secondary))
                                Text(exportSuccess ? "Data exported successfully!".localized : "Export Data (JSON Backup)".localized)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(exportSuccess ? .green : (isExportHovered ? .primary : .secondary))
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .onHover { isExportHovered = $0 }
                        #endif
                    }

                    // MARK: Account
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("ACCOUNT".localized)

                        VStack(alignment: .leading, spacing: 10) {
                            if let email = syncManager.userEmail {
                                HStack(spacing: 8) {
                                    Image(systemName: "envelope")
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundColor(.secondary)
                                    Text(email)
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Minimalist actions side by side
                            HStack(spacing: 20) {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        activeModal = .signOut
                                    }
                                }) {
                                    Text("Sign Out".localized)
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(isSignOutHovered ? .primary : .secondary)
                                        .padding(.vertical, 2)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                .onHover { isSignOutHovered = $0 }

                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        activeModal = .deleteAccount
                                    }
                                }) {
                                    Text("Delete Account".localized)
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(isDeleteHovered ? .red : .red.opacity(0.65))
                                        .padding(.vertical, 2)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                .onHover { isDeleteHovered = $0 }
                            }
                        }
                    }

                    // MARK: Support & Feedback
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("SUPPORT & FEEDBACK".localized)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("For feedback, inspiration or help:".localized)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)

                                Link("ch.wolters@tum.de", destination: URL(string: "mailto:ch.wolters@tum.de")!)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(isEmailHovered ? .primary : .secondary)
                                    .pointingHandCursor()
                                    .onHover { isEmailHovered = $0 }
                            }

                            HStack(spacing: 6) {
                                Text("Donations & Support:".localized)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)

                                Link("paypal.me/chrw0", destination: URL(string: "https://paypal.me/chrw0")!)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(isPaypalHovered ? .primary : .secondary)
                                    .pointingHandCursor()
                                    .onHover { isPaypalHovered = $0 }
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(40)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            // MARK: - Full Window Centered Custom Modal Popup
            if let modal = activeModal {
                modalOverlay(for: modal)
                    .transition(.opacity)
                    .zIndex(200)
            }
            
            if showImportModal {
                MigrationImportModalView(isPresented: $showImportModal)
                    .transition(.opacity)
                    .zIndex(300)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeModal)
        .onAppear {
            #if os(macOS)
            if #available(macOS 13.0, *) {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
            #endif
            Task {
                await notificationManager.refreshAuthorizationStatus()
            }
        }
    }

    private func handleNotificationToggle() {
        Task {
            await notificationManager.refreshAuthorizationStatus()
            if notificationManager.authorizationStatus == .notDetermined {
                let granted = await notificationManager.requestAuthorization()
                if granted {
                    notificationsEnabled = true
                    notificationManager.scheduleUpcomingBoundaryNotifications()
                } else {
                    notificationsEnabled = false
                }
            } else if notificationManager.authorizationStatus == .denied {
                notificationManager.openSystemNotificationSettings()
            } else {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    notificationsEnabled.toggle()
                }
                notificationManager.scheduleUpcomingBoundaryNotifications()
            }
        }
    }

    // MARK: - Modal Overlay

    @ViewBuilder
    private func modalOverlay(for modal: SettingsModalType) -> some View {
        ZStack {
            // Full-screen backdrop covering the entire window
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeModal = nil
                    }
                }

            // Modal Card Content
            VStack(alignment: .center, spacing: 20) {
                // Modal Title
                Text(modal == .deleteAccount ? "Delete Account".localized : "Sign Out".localized)
                    .font(.system(size: 16, weight: .light))
                    .tracking(1.0)
                    .foregroundColor(.primary)

                // Modal Body / Warning Text
                Text(modal == .deleteAccount
                    ? "Are you sure you want to delete your account? All your tasks, habits and scratchpad items will be permanently erased from all synced devices. This action cannot be undone.".localized
                    : "Are you sure you want to sign out? Your data will remain safely stored in your account and can be restored whenever you sign back in.".localized
                )
                .font(.system(size: 12, weight: .light))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

                // Action Buttons (Cancel / Confirm)
                HStack(spacing: 16) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeModal = nil
                        }
                    }) {
                        Text("Cancel".localized)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()

                    if modal == .deleteAccount {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                activeModal = nil
                            }
                            Task {
                                await syncManager.deleteAccount()
                            }
                        }) {
                            Text("Delete Everything".localized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    } else {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                activeModal = nil
                            }
                            syncManager.signOut()
                        }) {
                            Text("Sign Out".localized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(colorScheme == .dark ? .black : .white))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Color.primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
                .padding(.top, 10)
            }
            .padding(40)
            .background(Color(colorScheme == .dark ? .black : .white))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(radius: 20)
            .frame(maxWidth: 500)
            .padding(20)
            #if os(macOS)
            .onExitCommand {
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeModal = nil
                }
            }
            #endif
            .background(
                Button("") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeModal = nil
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
            )
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .light))
            .tracking(2.0)
            .foregroundColor(.secondary.opacity(0.7))
    }
}
