import SwiftUI

struct SettingsView: View {
    @ObservedObject private var locManager = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    var onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Header: Title & Close Button
            HStack {
                Text("SETTINGS".localized)
                    .font(.system(size: 11, weight: .light, design: .default))
                    .tracking(3.0)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Settings")
            }
            .padding(.bottom, 10)
            
            // Section: Language
            VStack(alignment: .leading, spacing: 14) {
                Text("LANGUAGE".localized)
                    .font(.system(size: 10, weight: .light, design: .default))
                    .tracking(2.0)
                    .foregroundColor(.secondary.opacity(0.7))
                
                HStack(spacing: 12) {
                    ForEach(AppLanguage.allCases) { lang in
                        let isSelected = locManager.currentLanguage == lang
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                locManager.currentLanguage = lang
                            }
                        }) {
                            HStack(spacing: 8) {
                                Text(lang.displayName)
                                    .font(.system(size: 12, weight: isSelected ? .medium : .light))
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                
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
                                    .fill(isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08) : Color.clear)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(isSelected ? 0.2 : 0.08), lineWidth: 1)
                            )
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
