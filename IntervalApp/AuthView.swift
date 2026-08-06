import SwiftUI

struct AuthView: View {
    @StateObject private var syncManager = SupabaseSyncManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
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
                    
                    Text(isSignUp ? "Create your account" : "Sign in to sync your devices")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.secondary)
                }
                
                // Form
                VStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EMAIL")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .tracking(3)
                        TextField("", text: $email)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .light))
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            #endif
                            .autocorrectionDisabled()
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(height: 0.5)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PASSWORD")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .tracking(3)
                        SecureField("", text: $password)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .light))
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(height: 0.5)
                    }
                }
                .frame(maxWidth: 300)
                
                // Error
                if let error = syncManager.authError {
                    Text(error)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.red.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .transition(.opacity)
                }
                
                // Submit
                Button(action: submit) {
                    Group {
                        if syncManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(colorScheme == .dark ? .black : .white)
                        } else {
                            Text(isSignUp ? "REGISTER" : "SIGN IN")
                                .font(.system(size: 12, weight: .medium))
                                .tracking(3)
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
                .disabled(!isFormValid || syncManager.isLoading)
                
                // Toggle mode
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { isSignUp.toggle() }
                    syncManager.authError = nil
                }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "No account? Register")
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
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
