import SwiftUI

struct SettingsView: View {
    @ObservedObject private var locManager = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredLang: AppLanguage? = nil
    var onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Header: Title
            HStack {
                Text("SETTINGS".localized)
                    .font(.system(size: 11, weight: .light, design: .default))
                    .tracking(3.0)
                    .foregroundColor(.gray)
                
                Spacer()
            }
            .padding(.bottom, 5)
            
            // Section: Language
            VStack(alignment: .leading, spacing: 14) {
                Text("LANGUAGE".localized)
                    .font(.system(size: 10, weight: .light, design: .default))
                    .tracking(2.0)
                    .foregroundColor(.secondary.opacity(0.7))
                
                HStack(spacing: 12) {
                    ForEach(AppLanguage.allCases) { lang in
                        let isSelected = locManager.currentLanguage == lang
                        let isHovered = hoveredLang == lang
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                locManager.currentLanguage = lang
                            }
                        }) {
                            HStack(spacing: 8) {
                                Text(lang.displayName)
                                    .font(.system(size: 12, weight: isSelected ? .medium : .light))
                                    .foregroundColor(isSelected ? .primary : (isHovered ? .primary : .secondary))
                                
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .light))
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(isSelected ? 0.25 : (isHovered ? 0.15 : 0.08)), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredLang = hovering ? lang : nil
                        }
                    }
                }
            }
            
            // Section: Support & Feedback
            VStack(alignment: .leading, spacing: 16) {
                Text("SUPPORT & FEEDBACK".localized)
                    .font(.system(size: 10, weight: .light, design: .default))
                    .tracking(2.0)
                    .foregroundColor(.secondary.opacity(0.7))
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("For feedback, inspiration or help contact:".localized)
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.secondary)
                        
                        Link(destination: URL(string: "mailto:ch.wolters@tum.de")!) {
                            Text("ch.wolters@tum.de")
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(.primary)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Donations & Support:".localized)
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.secondary)
                        
                        Link(destination: URL(string: "https://paypal.me/chrw0")!) {
                            Text("paypal.me/chrw0")
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(.primary)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
