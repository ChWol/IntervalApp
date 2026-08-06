import SwiftUI
import SwiftData

struct BinRowView: View {
    @Bindable var task: TaskItem
    let fontSize: CGFloat
    
    @Environment(\.modelContext) private var modelContext
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            Button(action: restoreTask) {
                HStack(spacing: 15) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: fontSize * 0.8, weight: .light))
                        .foregroundColor(.secondary)
                    
                    Text(task.text)
                        .font(.system(size: fontSize, weight: .light))
                        .foregroundColor(.secondary)
                        .strikethrough(task.completed)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button(action: deletePermanently) {
                Image(systemName: "xmark")
                    .font(.system(size: max(fontSize * 0.4, 11), weight: .light))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0.4)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private func restoreTask() {
        withAnimation {
            task.deletedAt = nil
            task.completed = false
            task.completedAt = nil
            task.updatedAt = Date()
            try? modelContext.save()
            SupabaseSyncManager.shared.push()
        }
    }
    
    private func deletePermanently() {
        withAnimation {
            let taskId = task.id
            modelContext.delete(task)
            try? modelContext.save()
            SupabaseSyncManager.shared.deleteRemote(table: "tasks", ids: [taskId])
        }
    }
}
