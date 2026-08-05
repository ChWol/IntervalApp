import SwiftUI
import SwiftData

@main
struct IntervalApp: App {
    var container: ModelContainer = {
        let schema = Schema([
            TaskItem.self,
            HabitItem.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return (try? ModelContainer(for: schema, configurations: [fallbackConfiguration])) ?? {
                fatalError("Could not create ModelContainer: \(error)")
            }()
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        // Only apply to macOS
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        #endif
    }
}
