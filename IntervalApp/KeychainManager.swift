import Foundation
import Security

// MARK: - Keychain Manager

final class KeychainManager {
    static let shared = KeychainManager()
    
    private let serviceName = "chw.IntervalApp"
    private let serverName = "interval.app"
    
    private init() {}
    
    // MARK: - Save Credential
    
    @discardableResult
    func saveCredential(email: String, password: String) -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty, !password.isEmpty,
              let passwordData = password.data(using: .utf8) else {
            return false
        }
        
        // 1. Save as Generic Password (for app internal Keychain retrieval)
        let genericQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: trimmedEmail
        ]
        
        SecItemDelete(genericQuery as CFDictionary)
        
        var genericAttributes = genericQuery
        genericAttributes[kSecValueData as String] = passwordData
        genericAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        
        let genericStatus = SecItemAdd(genericAttributes as CFDictionary, nil)
        
        // 2. Save as Internet Password (for system AutoFill / Passwords app detection)
        let internetQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: serverName,
            kSecAttrAccount as String: trimmedEmail
        ]
        
        SecItemDelete(internetQuery as CFDictionary)
        
        var internetAttributes = internetQuery
        internetAttributes[kSecValueData as String] = passwordData
        internetAttributes[kSecAttrLabel as String] = "Interval"
        internetAttributes[kSecAttrComment as String] = "Interval Account"
        internetAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        
        let internetStatus = SecItemAdd(internetAttributes as CFDictionary, nil)
        
        return genericStatus == errSecSuccess || internetStatus == errSecSuccess
    }
    
    // MARK: - Read Credential
    
    func getSavedPassword(for email: String) -> String? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty else { return nil }
        
        // Try generic password first
        let genericQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: trimmedEmail,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        var status = SecItemCopyMatching(genericQuery as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) {
            return password
        }
        
        // Try internet password
        let internetQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: serverName,
            kSecAttrAccount as String: trimmedEmail,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        result = nil
        status = SecItemCopyMatching(internetQuery as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) {
            return password
        }
        
        return nil
    }
    
    func getSavedCredentials() -> [(email: String, password: String)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: kCFBooleanTrue as Any,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }
        
        var credentials: [(email: String, password: String)] = []
        for dict in items {
            guard let account = dict[kSecAttrAccount as String] as? String,
                  let data = dict[kSecValueData as String] as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                continue
            }
            credentials.append((email: account, password: password))
        }
        return credentials
    }
    
    // MARK: - Delete Credential
    
    func deleteCredential(email: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        let genericQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: trimmedEmail
        ]
        SecItemDelete(genericQuery as CFDictionary)
        
        let internetQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: serverName,
            kSecAttrAccount as String: trimmedEmail
        ]
        SecItemDelete(internetQuery as CFDictionary)
    }
    
    // MARK: - Strong Password Generator
    
    func generateStrongPassword() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let upperLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let digits = "0123456789"
        
        func randomBlock(len: Int) -> String {
            let pool = letters + upperLetters + digits
            return String((0..<len).compactMap { _ in pool.randomElement() })
        }
        
        return "\(randomBlock(len: 3))-\(randomBlock(len: 3))-\(randomBlock(len: 3))"
    }
}
