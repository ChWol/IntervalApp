import SwiftUI
import SwiftData

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarManager.shared.setup(container: IntervalApp.sharedModelContainer)
    }

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

    static let sharedModelContainer: ModelContainer = {
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
            fatalError("Could not create persistent ModelContainer. Your data cannot be saved safely. Error: \(error)")
        }
    }()

    #if os(macOS)
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = true
    #endif

    var body: some Scene {
        WindowGroup(id: "main") {
            #if os(watchOS)
            WatchContentView()
            #else
            ContentView()
                .handlesExternalEvents(preferring: Set(arrayLiteral: "main"), allowing: Set(arrayLiteral: "*"))
                .onAppear {
                    #if os(macOS)
                    MenuBarManager.shared.setup(container: Self.sharedModelContainer)
                    #endif
                }
            #endif
        }
        .modelContainer(Self.sharedModelContainer)
        #if !os(watchOS)
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        #endif
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .printItem) {
                Button("Print / Save as PDF...".localized) {
                    PrintManager.printIntervals(context: IntervalApp.sharedModelContainer.mainContext)
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
        #endif
    }
}
