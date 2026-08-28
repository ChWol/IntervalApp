#if !os(watchOS)
import SwiftUI
import SwiftData

struct BinRowView: View {
    @Bindable var task: TaskItem
    let fontSize: CGFloat
    
    @Environment(\.modelContext) private var modelContext
    @State private var isHovering = false
    @State private var isUndoHovered = false
    @State private var isXHovered = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            Button(action: restoreTask) {
                HStack(spacing: 15) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: fontSize * 0.8, weight: .light))
                        .foregroundColor(isUndoHovered ? .primary : .secondary.opacity(0.6))
                    
                    Text(task.text)
                        .font(.system(size: fontSize, weight: .light))
                        .foregroundColor(.secondary)
                        .strikethrough(task.completed)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isUndoHovered = hovering
            }
            
            Spacer()
            
            Button(action: deletePermanently) {
                Image(systemName: "xmark")
                    .font(.system(size: max(fontSize * 0.4, 11), weight: .light))
                    .foregroundColor(isXHovered ? .primary : .secondary.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isXHovered = hovering
            }
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
            TaskHousekeeping.restore(task, in: modelContext)
        }
    }
    
    private func deletePermanently() {
        withAnimation {
            TaskHousekeeping.deletePermanently([task], in: modelContext)
        }
    }
}

#endif
