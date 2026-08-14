import SwiftUI

struct ShareListModalView: View {
    let list: ScratchpadList
    @Binding var isPresented: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var syncManager = SupabaseSyncManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    
    @State private var emailInput: String = ""
    @State private var members: [ScratchpadMemberDTO] = []
    @State private var isLoading: Bool = false
    @State private var isInviting: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var isCloseHovered: Bool = false
    @FocusState private var isEmailFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Ambient Backdrop
            Color.black.opacity(colorScheme == .dark ? 0.7 : 0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    closeModal()
                }
            
            VStack(alignment: .leading, spacing: 20) {
                // Header Row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Share List".localized)
                            .font(.system(size: 18, weight: .regular))
                        
                        Text(list.title)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button(action: closeModal) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(isCloseHovered ? .primary : .secondary.opacity(0.7))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { hovering in
                        isCloseHovered = hovering
                    }
                }
                
                // Email Invitation Input
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TextField("Enter email address...".localized, text: $emailInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .light))
                            .focused($isEmailFieldFocused)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .onSubmit {
                                invite()
                            }
                        
                        Button(action: invite) {
                            HStack(spacing: 6) {
                                if isInviting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Invite".localized)
                                        .font(.system(size: 13, weight: .medium))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.primary)
                            .foregroundColor(Color(colorScheme == .dark ? .black : .white))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .disabled(emailInput.trimmingCharacters(in: .whitespaces).isEmpty || isInviting)
                    }
                    
                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(.red)
                    }
                    
                    if let succ = successMessage {
                        Text(succ)
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(.green)
                    }
                }
                
                Divider()
                    .opacity(0.3)
                
                // Members List
                VStack(alignment: .leading, spacing: 12) {
                    Text("MEMBERS".localized)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                    
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .padding(.vertical, 16)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                // Current User as Owner / Member
                                HStack {
                                    Circle()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text(String((syncManager.userEmail ?? "U").prefix(1)).uppercased())
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.secondary)
                                        )
                                    
                                    Text(syncManager.userEmail ?? "You")
                                        .font(.system(size: 13, weight: .light))
                                    
                                    Spacer()
                                    
                                    Text("Owner".localized)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                                }
                                .padding(.vertical, 4)
                                
                                // Collaborators
                                ForEach(members) { member in
                                    MemberRowView(member: member) {
                                        remove(member)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 24, y: 10)
            )
            .frame(maxWidth: 460)
            .padding(20)
            .background(
                Button(action: closeModal) {
                    EmptyView()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
            )
        }
        #if os(macOS)
        .onExitCommand {
            closeModal()
        }
        #endif
        .onAppear {
            isEmailFieldFocused = true
            loadMembers()
            #if os(macOS)
            setupKeyboardMonitor()
            #endif
        }
        .onDisappear {
            #if os(macOS)
            removeKeyboardMonitor()
            #endif
        }
    }
    
    #if os(macOS)
    @State private var eventMonitor: Any?
    
    private func setupKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isPresented else { return event }
            if event.keyCode == 53 { // Escape
                closeModal()
                return nil
            }
            return event
        }
    }
    
    private func removeKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    #endif
    
    private func closeModal() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isPresented = false
        }
    }
    
    private func loadMembers() {
        isLoading = true
        Task {
            let fetched = await syncManager.fetchMembers(for: list.id)
            await MainActor.run {
                self.members = fetched
                self.isLoading = false
            }
        }
    }
    
    private func invite() {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return }
        
        errorMessage = nil
        successMessage = nil
        isInviting = true
        
        Task {
            let result = await syncManager.inviteCollaborator(listId: list.id, email: email)
            await MainActor.run {
                self.isInviting = false
                if result.success {
                    self.emailInput = ""
                    self.successMessage = "Invited".localized + " \(email)"
                    self.loadMembers()
                } else {
                    self.errorMessage = result.error ?? "Failed to invite".localized
                }
            }
        }
    }
    
    private func remove(_ member: ScratchpadMemberDTO) {
        Task {
            let success = await syncManager.removeCollaborator(memberId: member.id)
            if success {
                await MainActor.run {
                    self.members.removeAll { $0.id == member.id }
                }
            }
        }
    }
}

// MARK: - Member Row Component

private struct MemberRowView: View {
    let member: ScratchpadMemberDTO
    let onRemove: () -> Void
    
    @State private var isRemoveHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Text(String(member.invited_email.prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                )
            
            Text(member.invited_email)
                .font(.system(size: 13, weight: .light))
            
            Spacer()
            
            Text("Member".localized)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
            
            // Accented remove button with pointer / clickhand
            Button(action: onRemove) {
                ZStack {
                    if isRemoveHovered {
                        Circle()
                            .fill(Color.red.opacity(0.12))
                    }
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isRemoveHovered ? .red : .secondary.opacity(0.6))
                }
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Remove".localized)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isRemoveHovered = hovering
                }
            }
        }
        .padding(.vertical, 4)
    }
}
