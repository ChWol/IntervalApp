import SwiftUI

struct AuthView: View {
    enum AuthMode {
        case signIn
        case signUp
        case forgotPassword
    }
    
    @StateObject private var syncManager = SupabaseSyncManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var authMode: AuthMode = .signIn
    @State private var isPasswordVisible: Bool = false
    @State private var successMessage: String? = nil
    
    @State private var isToggleHovered = false
    @State private var isForgotHovered = false
    @State private var isBackHovered = false
    @State private var isEyeHovered = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
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
                    
                    Text(subtitleText)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.secondary)
                }
                
                // Form fields
                VStack(spacing: 18) {
                    // Email Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EMAIL".localized)
                            .font(.system(size: 10, weight: .light))
                            .tracking(2)
                            .foregroundColor(.secondary)
                        
                        TextField("", text: $email)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .light))
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                            .padding(.bottom, 6)
                            .overlay(
                                Rectangle()
                                    .fill(Color.primary.opacity(0.15))
                                    .frame(height: 0.5),
                                alignment: .bottom
                            )
                    }
                    
                    // Password Field (Only for Sign In / Sign Up)
                    if authMode != .forgotPassword {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PASSWORD".localized)
                                .font(.system(size: 10, weight: .light))
                                .tracking(2)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                Group {
                                    if isPasswordVisible {
                                        TextField("", text: $password)
                                    } else {
                                        SecureField("", text: $password)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .light))
                                .textContentType(authMode == .signUp ? .newPassword : .password)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .onSubmit {
                                    if isFormValid { submit() }
                                }
                                
                                Button(action: {
                                    isPasswordVisible.toggle()
                                }) {
                                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(isEyeHovered ? .primary : .secondary.opacity(0.6))
                                        .padding(4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                .help(isPasswordVisible ? "Hide password".localized : "Show password".localized)
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        isEyeHovered = hovering
                                    }
                                }
                            }
                            .padding(.bottom, 6)
                            .overlay(
                                Rectangle()
                                    .fill(Color.primary.opacity(0.15))
                                    .frame(height: 0.5),
                                alignment: .bottom
                            )
                            
                            // Forgot Password Link in Sign In mode
                            if authMode == .signIn {
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            authMode = .forgotPassword
                                            syncManager.authError = nil
                                            successMessage = nil
                                        }
                                    }) {
                                        Text("Forgot password?".localized)
                                            .font(.system(size: 10, weight: .light))
                                            .foregroundColor(isForgotHovered ? .primary : .secondary.opacity(0.7))
                                            .underline(isForgotHovered, color: .primary)
                                            .padding(.top, 2)
                                    }
                                    .buttonStyle(.plain)
                                    .pointingHandCursor()
                                    .onHover { hovering in
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            isForgotHovered = hovering
                                        }
                                    }
                                }
                            }
                            
                            // Password length hint for sign up
                            if authMode == .signUp && !password.isEmpty && password.count < 6 {
                                Text("Password must be at least 6 characters".localized)
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
                .frame(maxWidth: 300)
                
                // Feedback Messages
                VStack(spacing: 8) {
                    if let error = syncManager.authError {
                        Text(error)
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }
                    
                    if let succ = successMessage {
                        Text(succ)
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(.green)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }
                }
                
                // Submit button
                Button(action: submit) {
                    ZStack {
                        if syncManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(submitButtonTitle)
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
                
                // Navigation / Mode Switcher
                Group {
                    if authMode == .forgotPassword {
                        // Back to Sign In Link
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                authMode = .signIn
                                syncManager.authError = nil
                                successMessage = nil
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 10, weight: .light))
                                Text("Back to Sign In".localized)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(isBackHovered ? .primary : .secondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                Capsule()
                                    .fill(isBackHovered ? Color.primary.opacity(0.06) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.12)) {
                                isBackHovered = hovering
                            }
                        }
                    } else {
                        // Sign In <-> Sign Up Toggle
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                authMode = (authMode == .signIn) ? .signUp : .signIn
                                syncManager.authError = nil
                                successMessage = nil
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(authMode == .signUp ? "Already have an account?".localized : "No account?".localized)
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(.secondary)
                                
                                Text(authMode == .signUp ? "Sign In".localized : "Register".localized)
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
                    }
                }
                
                Spacer()
                Spacer()
            }
            .padding(40)
        }
    }
    
    private var subtitleText: String {
        switch authMode {
        case .signIn:
            return "Sign in to sync your devices".localized
        case .signUp:
            return "Create your account".localized
        case .forgotPassword:
            return "Enter your email to receive a recovery link".localized
        }
    }
    
    private var submitButtonTitle: String {
        switch authMode {
        case .signIn:
            return "SIGN IN".localized
        case .signUp:
            return "REGISTER".localized
        case .forgotPassword:
            return "SEND RESET LINK".localized
        }
    }
    
    private var isFormValid: Bool {
        let isEmailValid = !email.trimmingCharacters(in: .whitespaces).isEmpty && email.contains("@")
        switch authMode {
        case .signIn, .signUp:
            return isEmailValid && password.count >= 6
        case .forgotPassword:
            return isEmailValid
        }
    }
    
    private func submit() {
        syncManager.authError = nil
        successMessage = nil
        
        Task {
            switch authMode {
            case .signIn:
                await syncManager.signIn(email: email, password: password)
            case .signUp:
                await syncManager.signUp(email: email, password: password)
            case .forgotPassword:
                let result = await syncManager.resetPassword(email: email)
                if result.success {
                    successMessage = "Password reset link sent! Check your inbox.".localized
                } else {
                    syncManager.authError = result.error
                }
            }
        }
    }
}
