import SwiftUI
import SwiftData

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            SupabaseSyncManager.shared.handleIncomingURL(url)
        }
    }
}
#endif

@main
struct IntervalApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TaskItem.self,
            HabitItem.self,
            ScratchpadList.self,
            ScratchpadItem.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Failed to create persistent ModelContainer: \(error). Using in-memory fallback...")
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    #if os(macOS)
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = true
    #endif

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .handlesExternalEvents(preferring: Set(arrayLiteral: "main"), allowing: Set(arrayLiteral: "*"))
                .onAppear {
                    #if os(macOS)
                    MenuBarManager.shared.setup(container: sharedModelContainer)
                    #endif
                }
        }
        .modelContainer(sharedModelContainer)
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .printItem) {
                Button("Print / Save as PDF...".localized) {
                    PrintManager.printIntervals(context: sharedModelContainer.mainContext)
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
        #endif
    }
}
