import SwiftUI
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
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showHabits") private var showHabits: Bool = true
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled: Bool = true

    @State private var hoveredLang: AppLanguage? = nil
    @State private var activeModal: SettingsModalType? = nil
    @State private var isSignOutHovered: Bool = false
    @State private var isDeleteHovered: Bool = false
    var onClose: () -> Void

    var body: some View {
        ZStack {
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

                    HStack(spacing: 10) {
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

                // MARK: Preferences (Habits & Sound Effects)
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("PREFERENCES".localized)

                    MinimalistToggle(isOn: $showHabits, label: "Show Habits Bar".localized)
                    MinimalistToggle(isOn: $soundEffectsEnabled, label: "Sound Effects".localized)
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

                Spacer()
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // MARK: - Full Window Centered Custom Modal Popup (MigrationModal style)
            if let modal = activeModal {
                modalOverlay(for: modal)
                    .transition(.opacity)
                    .zIndex(200)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeModal)
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

            VStack(alignment: .leading, spacing: 20) {
                Text(modal == .deleteAccount ? "Delete Account".localized : "Sign Out".localized)
                    .font(.title)
                    .fontWeight(.light)
                    .foregroundColor(modal == .deleteAccount ? .red : .primary)

                Text(modal == .deleteAccount
                     ? "Are you sure you want to delete your account? All your tasks, habits, and custom lists will be permanently erased from the database and all devices. This cannot be undone.".localized
                     : "Are you sure you want to sign out? Your tasks and habits will remain safely synced on the server.".localized)
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeModal = nil
                        }
                    }) {
                        Text("Cancel".localized)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                            )
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
