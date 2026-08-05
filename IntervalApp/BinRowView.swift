import SwiftUI
import SwiftData

struct BinRowView: View {
    @Bindable var task: TaskItem
    let fontSize: CGFloat
    
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            Button(action: {
                withAnimation {
                    task.deletedAt = nil
                    task.completed = false
                    task.completedAt = nil
                }
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: fontSize * 0.8, weight: .light))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Text(task.text)
                .font(.system(size: fontSize, weight: .light))
                .foregroundColor(.secondary)
                .strikethrough(task.completed)
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
