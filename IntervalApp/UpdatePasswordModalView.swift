import SwiftUI

struct UpdatePasswordModalView: View {
    @Binding var isPresented: Bool
    
    @ObservedObject private var syncManager = SupabaseSyncManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var isCloseHovered = false
    @State private var isEyeHovered = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isSubmitting { isPresented = false }
                }
            
            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set New Password".localized)
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(.primary)
                        
                        Text("Enter your new password below".localized)
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(isCloseHovered ? .primary : .secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(isCloseHovered ? Color.primary.opacity(0.08) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { isCloseHovered = $0 }
                }
                
                // Form Fields
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("New Password".localized)
                            .font(.system(size: 10, weight: .light))
                            .tracking(2)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            if isPasswordVisible {
                                TextField("", text: $newPassword)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14, weight: .light))
                                    .textContentType(.newPassword)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("", text: $newPassword)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14, weight: .light))
                                    .textContentType(.newPassword)
                                    .autocorrectionDisabled()
                            }
                            
                            Button(action: { isPasswordVisible.toggle() }) {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(isEyeHovered ? .primary : .secondary.opacity(0.6))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .onHover { isEyeHovered = $0 }
                        }
                        .padding(.bottom, 6)
                        .overlay(
                            Rectangle()
                                .fill(Color.primary.opacity(0.15))
                                .frame(height: 0.5),
                            alignment: .bottom
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Confirm Password".localized)
                            .font(.system(size: 10, weight: .light))
                            .tracking(2)
                            .foregroundColor(.secondary)
                        
                        if isPasswordVisible {
                            TextField("", text: $confirmPassword)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .light))
                                .textContentType(.newPassword)
                                .autocorrectionDisabled()
                                .padding(.bottom, 6)
                                .overlay(
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.15))
                                        .frame(height: 0.5),
                                    alignment: .bottom
                                )
                        } else {
                            SecureField("", text: $confirmPassword)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .light))
                                .textContentType(.newPassword)
                                .autocorrectionDisabled()
                                .padding(.bottom, 6)
                                .overlay(
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.15))
                                        .frame(height: 0.5),
                                    alignment: .bottom
                                )
                        }
                    }
                }
                
                // Feedback
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                if let succ = successMessage {
                    Text(succ)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                }
                
                // Submit Button
                Button(action: savePassword) {
                    ZStack {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("SAVE NEW PASSWORD".localized)
                                .font(.system(size: 11, weight: .medium))
                                .tracking(2)
                        }
                    }
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isValid ? Color.primary : Color.primary.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .disabled(!isValid || isSubmitting)
            }
            .padding(28)
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 24, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        #if os(macOS)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 && isPresented {
                    isPresented = false
                    return nil
                }
                return event
            }
        }
        #endif
    }
    
    private var isValid: Bool {
        newPassword.count >= 6 && newPassword == confirmPassword
    }
    
    private func savePassword() {
        guard newPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters".localized
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match".localized
            return
        }
        
        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            let result = await syncManager.updateUserPassword(newPassword: newPassword)
            await MainActor.run {
                self.isSubmitting = false
                if result.success {
                    if let email = self.syncManager.userEmail {
                        KeychainManager.shared.saveCredential(email: email, password: self.newPassword)
                    }
                    self.successMessage = "Password updated successfully!".localized
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        self.isPresented = false
                    }
                } else {
                    self.errorMessage = result.error ?? "Failed to update password"
                }
            }
        }
    }
}
