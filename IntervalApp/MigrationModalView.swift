import SwiftUI

struct MigrationModalView: View {
    let migration: Migration
    let tasks: [TaskItem]
    let onMigrate: (Set<String>) -> Void
    let onSkip: () -> Void
    
    @State private var selectedTaskIds: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 20) {
                Text("Migrate Tasks?")
                    .font(.title)
                    .fontWeight(.light)
                
                Text("A new \(migration.dest.lowercased()) has begun. Would you like to move these incomplete tasks from your \(migration.source) list to your new \(migration.dest) list?")
                    .foregroundColor(.secondary)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if tasks.isEmpty {
                            Text("No incomplete tasks to transfer.")
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(tasks) { task in
                                Button(action: {
                                    if selectedTaskIds.contains(task.id) {
                                        selectedTaskIds.remove(task.id)
                                    } else {
                                        selectedTaskIds.insert(task.id)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: selectedTaskIds.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedTaskIds.contains(task.id) ? .primary : .secondary)
                                        Text(task.text)
                                            .fontWeight(.light)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
                
                HStack {
                    Spacer()
                    Button("Skip") { onSkip() }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary, lineWidth: 1))
                    
                    Button("Migrate") { onMigrate(selectedTaskIds) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(Color.primary)
                        .foregroundColor(Color(colorScheme == .dark ? .black : .white))
                        .cornerRadius(8)
                }
                .padding(.top, 10)
            }
            .padding(40)
            .background(Color(colorScheme == .dark ? .black : .white))
            .cornerRadius(16)
            .shadow(radius: 20)
            .frame(maxWidth: 500)
            .padding(20)
        }
        .onAppear {
            selectedTaskIds = Set(tasks.map { $0.id })
        }
    }
}
