import SwiftUI
import SwiftData

@main
struct IntervalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TaskItem.self)
        // Only apply to macOS
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        #endif
    }
}
