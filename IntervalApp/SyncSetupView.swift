import SwiftUI

struct SyncSetupView: View {
    @Binding var syncKeyInput: String
    let onConfirm: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Sync Setup")
                .font(.system(size: 24, weight: .bold))
            
            Text("Enter a sync code to link your devices.\nUse the same code on your Mac and iPhone.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            TextField("Sync code (e.g. your name)", text: $syncKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .padding(.top, 8)
            
            Button(action: onConfirm) {
                Text("Start Sync")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(syncKeyInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(syncKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            
            Spacer()
        }
        .frame(minWidth: 340, minHeight: 300)
        .padding(30)
    }
}
