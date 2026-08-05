import SwiftUI

struct MigrationModalView: View {
    let migration: Migration
    let tasks: [TaskItem]
    let onMigrate: (Set<String>) -> Void
    let onSkip: () -> Void
    
    @State private var selectedTaskIds: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme
    
    private var modalTitle: String {
        switch (migration.source, migration.dest) {
        case ("1 Day", "1 Hour"):
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:00"
            let timeString = formatter.string(from: Date())
            return "It's \(timeString)!"
        case ("1 Week", "1 Day"):
            return "It's a new day – let's get it on!"
        case ("1 Month", "1 Week"):
            return "Fresh start into the next week – let's do some planning!"
        case ("1 Year", "1 Month"):
            return "Time to reflect on your yearly goals!"
        case ("1 Year", "1 Year"):
            return "Happy New Year!"
        default:
            return "Migrate Tasks"
        }
    }
    
    private var modalSubtitle: String {
        switch (migration.source, migration.dest) {
        case ("1 Day", "1 Hour"):
            return "Want to move any of these tasks to your next hour's focus?"
        case ("1 Week", "1 Day"):
            return "Let's plan the day! What should be your top goals based on what you planned for the week?"
        case ("1 Month", "1 Week"):
            return "What should be the top goals for the week based on what you planned for the month?"
        case ("1 Year", "1 Month"):
            return "What should this month be about? Select items from your 1 Year list to focus on this month."
        case ("1 Year", "1 Year"):
            return "New year, new you? What should we plan for the year? Take some time to set your goals."
        default:
            return "Would you like to transfer these tasks?"
        }
    }
    
    var body: some View {
        ZStack {
            // Darkened/greyed out backdrop for strong modal focus
            Color.black.opacity(0.75).ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 20) {
                Text(modalTitle)
                    .font(.title)
                    .fontWeight(.light)
                
                Text(modalSubtitle)
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                
                if migration.source == "1 Year" && migration.dest == "1 Year" {
                    // Special 1 Year goal setting prompt
                    Text("Use your 1 Year list in the app to set your new goals.")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 10)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if tasks.isEmpty {
                                Text("No incomplete tasks available to transfer.")
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
                }
                
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
            // By default, NONE should be selected yet
            selectedTaskIds = []
        }
    }
}
