import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
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

// MARK: - Settings Modal Action Type

enum SettingsModalType {
    case signOut
    case deleteAccount
}

struct SettingsView: View {
    @ObservedObject private var locManager = LocalizationManager.shared
    @ObservedObject private var syncManager = SupabaseSyncManager.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showHabits") private var showHabits: Bool = true
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled: Bool = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    
    // Active Sound Choices
    @AppStorage("selectedSoundComplete") private var selectedSoundComplete: String = SoundCompleteOption.clickWood.rawValue
    @AppStorage("selectedSoundDelete") private var selectedSoundDelete: String = SoundDeleteOption.paperSweep.rawValue
    @AppStorage("selectedSoundTransfer") private var selectedSoundTransfer: String = SoundTransferOption.velvetGlide.rawValue
    @AppStorage("selectedSoundRestore") private var selectedSoundRestore: String = SoundRestoreOption.reverseWhoosh.rawValue
    @AppStorage("selectedSoundTransition") private var selectedSoundTransition: String = SoundTransitionOption.zenBowl.rawValue
    @AppStorage("selectedSoundHabit") private var selectedSoundHabit: String = SoundHabitOption.wood.rawValue

    @State private var hoveredLang: AppLanguage? = nil
    @State private var activeModal: SettingsModalType? = nil
    @State private var isSignOutHovered: Bool = false
    @State private var isDeleteHovered: Bool = false
    @State private var isSystemSettingsHovered: Bool = false
    @State private var isImportHovered: Bool = false
    @State private var showImportModal: Bool = false
    @State private var playingEffect: SoundEffect? = nil
    @State private var hoveredSoundId: String? = nil
    @State private var hoveredMigrationId: String? = nil
    
    var onClose: () -> Void

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    // Header: Title
                    Text("SETTINGS".localized)
                        .font(.system(size: 11, weight: .light))
                        .tracking(3.0)
                        .foregroundColor(.gray)
                        .padding(.bottom, 2)

                    // MARK: Language
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("LANGUAGE".localized)

                        HStack(spacing: 8) {
                            ForEach(AppLanguage.allCases) { lang in
                                let isSelected = locManager.currentLanguage == lang
                                let isHov = hoveredLang == lang

                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        locManager.currentLanguage = lang
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Text(lang.displayName)
                                            .font(.system(size: 12, weight: isSelected ? .medium : .light))
                                            .foregroundColor(isSelected ? .primary : (isHov ? .primary : .secondary))

                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .light))
                                                .foregroundColor(.primary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
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

                    // MARK: Preferences (Habits, Sounds & Notifications)
                    VStack(alignment: .leading, spacing: 14) {
                        sectionLabel("PREFERENCES".localized)

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
                                                .font(.system(size: 10, weight: .medium))
                                            Image(systemName: "arrow.up.forward.app")
                                                .font(.system(size: 9))
                                        }
                                        .foregroundColor(isSystemSettingsHovered ? .primary : .primary.opacity(0.85))
                                        .underline()
                                    }
                                    .buttonStyle(.plain)
                                    .pointingHandCursor()
                                    .onHover { isSystemSettingsHovered = $0 }
                                }
                                .padding(.top, 2)
                            }
                        }
                    }

                    // MARK: - Sound Laboratory
                    if soundEffectsEnabled {
                        VStack(alignment: .leading, spacing: 18) {
                            sectionLabel("SOUND LABORATORY".localized)

                            // 1. Task Complete
                            soundCategoryGroup(
                                title: "TASK COMPLETION".localized,
                                options: SoundCompleteOption.allCases.map { ($0.rawValue, $0.displayName, $0.effect) },
                                selectedRawValue: selectedSoundComplete
                            ) { raw in
                                selectedSoundComplete = raw
                            }

                            // 2. Task Delete
                            soundCategoryGroup(
                                title: "TASK DELETION".localized,
                                options: SoundDeleteOption.allCases.map { ($0.rawValue, $0.displayName, $0.effect) },
                                selectedRawValue: selectedSoundDelete
                            ) { raw in
                                selectedSoundDelete = raw
                            }

                            // 3. Transfer
                            soundCategoryGroup(
                                title: "TRANSFER & MOVE".localized,
                                options: SoundTransferOption.allCases.map { ($0.rawValue, $0.displayName, $0.effect) },
                                selectedRawValue: selectedSoundTransfer
                            ) { raw in
                                selectedSoundTransfer = raw
                            }

                            // 4. Restore / Undo
                            soundCategoryGroup(
                                title: "RESTORE & UNDO".localized,
                                options: SoundRestoreOption.allCases.map { ($0.rawValue, $0.displayName, $0.effect) },
                                selectedRawValue: selectedSoundRestore
                            ) { raw in
                                selectedSoundRestore = raw
                            }

                            // 5. Transitions & Migration
                            soundCategoryGroup(
                                title: "TRANSITIONS & MIGRATION".localized,
                                options: SoundTransitionOption.allCases.map { ($0.rawValue, $0.displayName, $0.effect) },
                                selectedRawValue: selectedSoundTransition
                            ) { raw in
                                selectedSoundTransition = raw
                            }

                            // 6. Habit Check
                            soundCategoryGroup(
                                title: "HABIT CHECK".localized,
                                options: SoundHabitOption.allCases.map { ($0.rawValue, $0.displayName, $0.effect) },
                                selectedRawValue: selectedSoundHabit
                            ) { raw in
                                selectedSoundHabit = raw
                            }
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity)
                    }

                    // MARK: - Manual Interval Review & Migration
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("INTERVAL REVIEW & MIGRATION".localized)
                        
                        Text("Manually start an interval review to reflect, reorganize, and plan your tasks:".localized)
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 6) {
                            migrationButton(
                                id: "day",
                                title: "Daily Review & Planning".localized,
                                subtitle: "Plan today's tasks from your 1 Week list".localized,
                                icon: "sun.max",
                                source: "1 Week",
                                dest: "1 Day"
                            )
                            
                            migrationButton(
                                id: "week",
                                title: "Weekly Review & Planning".localized,
                                subtitle: "Plan the upcoming week from your 1 Month list".localized,
                                icon: "calendar",
                                source: "1 Month",
                                dest: "1 Week"
                            )
                            
                            migrationButton(
                                id: "month",
                                title: "Monthly Review & Realignment".localized,
                                subtitle: "Plan this month from your 1 Year goals".localized,
                                icon: "calendar.badge.clock",
                                source: "1 Year",
                                dest: "1 Month"
                            )
                            
                            migrationButton(
                                id: "year",
                                title: "Annual Goals & Reflection".localized,
                                subtitle: "Review and set your long-term goals for the year".localized,
                                icon: "sparkles",
                                source: "1 Year",
                                dest: "1 Year"
                            )
                        }
                    }

                    // MARK: - Data & Import
                    VStack(alignment: .leading, spacing: 12) {
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
                                    .font(.system(size: 13, weight: .regular))
                            }
                            .foregroundColor(isImportHovered ? .primary : .primary.opacity(0.85))
                            .underline()
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .onHover { isImportHovered = $0 }
                    }

                    // MARK: Support & Feedback
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("SUPPORT & FEEDBACK".localized)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("For feedback, inspiration or help:".localized)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)

                                Link("ch.wolters@tum.de", destination: URL(string: "mailto:ch.wolters@tum.de")!)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .underline()
                                    .pointingHandCursor()
                            }

                            HStack(spacing: 6) {
                                Text("Donations & Support:".localized)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)

                                Link("paypal.me/chrw0", destination: URL(string: "https://paypal.me/chrw0")!)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .underline()
                                    .pointingHandCursor()
                            }
                        }
                    }

                    // MARK: Account
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("ACCOUNT".localized)

                        VStack(alignment: .leading, spacing: 14) {
                            if let email = syncManager.userEmail {
                                HStack(spacing: 8) {
                                    Image(systemName: "envelope")
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundColor(.secondary)
                                    Text(email)
                                        .font(.system(size: 13, weight: .light))
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Minimalist text items side by side
                            HStack(spacing: 24) {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        activeModal = .signOut
                                    }
                                }) {
                                    Text("Sign Out".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(isSignOutHovered ? .primary : .primary.opacity(0.85))
                                        .underline()
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
                                        .font(.system(size: 13, weight: .light))
                                        .foregroundColor(isDeleteHovered ? .red : .red.opacity(0.75))
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                .onHover { isDeleteHovered = $0 }
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

    // MARK: - Sound Category Group Component

    @ViewBuilder
    private func soundCategoryGroup(
        title: String,
        options: [(id: String, name: String, effect: SoundEffect)],
        selectedRawValue: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .tracking(1.5)
                .foregroundColor(.secondary.opacity(0.8))

            HStack(spacing: 8) {
                ForEach(options, id: \.id) { opt in
                    let isSelected = selectedRawValue == opt.id
                    let isHov = hoveredSoundId == opt.id
                    let isPlaying = playingEffect == opt.effect

                    HStack(spacing: 6) {
                        // Play / Preview Button
                        Button(action: {
                            previewSound(opt.effect)
                        }) {
                            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()

                        // Sound Name (Tap to select)
                        Button(action: {
                            previewSound(opt.effect)
                            withAnimation(.easeInOut(duration: 0.12)) {
                                onSelect(opt.id)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(opt.name)
                                    .font(.system(size: 11, weight: isSelected ? .medium : .light))
                                    .foregroundColor(isSelected ? .primary : (isHov ? .primary : .secondary))

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .light))
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
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
                    .onHover { hoveredSoundId = $0 ? opt.id : nil }
                }
            }
        }
    }

    private func previewSound(_ effect: SoundEffect) {
        withAnimation(.easeInOut(duration: 0.1)) {
            playingEffect = effect
        }
        SoundManager.shared.play(effect, volume: 1.0, ignoreMute: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if playingEffect == effect {
                withAnimation(.easeInOut(duration: 0.15)) {
                    playingEffect = nil
                }
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

    @ViewBuilder
    private func migrationButton(id: String, title: String, subtitle: String, icon: String, source: String, dest: String) -> some View {
        let isHovered = hoveredMigrationId == id
        Button(action: {
            MigrationManager.shared.triggerManualMigration(source: source, dest: dest)
            onClose()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(isHovered ? .primary : .secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(isHovered ? .primary : .primary.opacity(0.85))
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(isHovered ? .primary : .secondary.opacity(0.4))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(colorScheme == .dark ? (isHovered ? 0.08 : 0.04) : (isHovered ? 0.06 : 0.02)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredMigrationId = h ? id : nil
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .light))
            .tracking(2.0)
            .foregroundColor(.secondary.opacity(0.7))
    }
}
