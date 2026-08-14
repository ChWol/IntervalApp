import SwiftUI

struct AuthView: View {
    @StateObject private var syncManager = SupabaseSyncManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isToggleHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white)
                .ignoresSafeArea()
            
            VStack(spacing: 36) {
                Spacer()
                
                // App branding
                VStack(spacing: 16) {
                    Text("INTERVAL")
                        .font(.system(size: 32, weight: .ultraLight))
                        .tracking(10)
                        .foregroundColor(.primary)
                    
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 40, height: 0.5)
                    
                    Text(isSignUp ? "Create your account".localized : "Sign in to sync your devices".localized)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.secondary)
                }
                
                // Form fields
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EMAIL".localized)
                            .font(.system(size: 10, weight: .light))
                            .tracking(2)
                            .foregroundColor(.secondary)
                        
                        TextField("", text: $email)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .light))
                            .padding(.bottom, 6)
                            .overlay(
                                Rectangle()
                                    .fill(Color.primary.opacity(0.15))
                                    .frame(height: 0.5),
                                alignment: .bottom
                            )
                            #if os(iOS)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            #endif
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PASSWORD".localized)
                            .font(.system(size: 10, weight: .light))
                            .tracking(2)
                            .foregroundColor(.secondary)
                        
                        SecureField("", text: $password)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .light))
                            .padding(.bottom, 6)
                            .overlay(
                                Rectangle()
                                    .fill(Color.primary.opacity(0.15))
                                    .frame(height: 0.5),
                                alignment: .bottom
                            )
                            .onSubmit {
                                if isFormValid { submit() }
                            }
                    }
                }
                .frame(maxWidth: 300)
                
                // Error display
                if let error = syncManager.authError {
                    Text(error)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                
                // Submit button
                Button(action: submit) {
                    ZStack {
                        if syncManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(isSignUp ? "REGISTER".localized : "SIGN IN".localized)
                                .font(.system(size: 11, weight: .medium))
                                .tracking(2)
                        }
                    }
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: 300)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isFormValid ? Color.primary : Color.primary.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .disabled(!isFormValid || syncManager.isLoading)
                
                // Toggle mode with accented text and clickhand cursor
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { isSignUp.toggle() }
                    syncManager.authError = nil
                }) {
                    HStack(spacing: 4) {
                        Text(isSignUp ? "Already have an account?".localized : "No account?".localized)
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(.secondary)
                        
                        Text(isSignUp ? "Sign In".localized : "Register".localized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isToggleHovered ? .primary : .primary.opacity(0.85))
                            .underline(isToggleHovered, color: .primary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule()
                            .fill(isToggleHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isToggleHovered = hovering
                    }
                }
                
                Spacer()
                Spacer()
            }
            .padding(40)
        }
    }
    
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }
    
    private func submit() {
        Task {
            if isSignUp {
                await syncManager.signUp(email: email, password: password)
            } else {
                await syncManager.signIn(email: email, password: password)
            }
        }
    }
}
