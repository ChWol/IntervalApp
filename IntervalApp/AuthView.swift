import SwiftUI

struct AuthView: View {
    @StateObject private var syncManager = SupabaseSyncManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            
            Text(isSignUp ? "Create Account" : "Sign In")
                .font(.system(size: 24, weight: .bold))
            
            Text("Sync your tasks & habits across all devices.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .autocorrectionDisabled()
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: 280)
            
            if let error = syncManager.authError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            
            Button(action: submit) {
                Group {
                    if syncManager.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(isSignUp ? "Register" : "Sign In")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: 200)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isFormValid ? Color.accentColor : Color.gray.opacity(0.5))
                )
            }
            .buttonStyle(.plain)
            .disabled(!isFormValid || syncManager.isLoading)
            
            Button(action: { 
                withAnimation { isSignUp.toggle() }
                syncManager.authError = nil
            }) {
                Text(isSignUp ? "Already have an account? Sign In" : "No account yet? Register")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .frame(minWidth: 340, minHeight: 360)
        .padding(30)
    }
    
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6
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
