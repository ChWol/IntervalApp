import SwiftUI
import SwiftData

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if IntervalApp.modelBootstrap.startupError == nil {
            MenuBarManager.shared.setup(container: IntervalApp.sharedModelContainer)
        }
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

    static let modelBootstrap: ContainerBootstrapResult = {
        let schema = Schema([
            TaskItem.self,
            HabitItem.self,
            ScratchpadList.self,
            ScratchpadItem.self
        ])
        return PersistentContainerBootstrap.load(schema: schema)
    }()
    static let sharedModelContainer = modelBootstrap.container

    #if os(macOS)
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = true
    #endif

    var body: some Scene {
        WindowGroup(id: "main") {
            if let startupError = Self.modelBootstrap.startupError {
                DataStoreUnavailableView(message: startupError)
            } else {
                #if os(watchOS)
                WatchContentView()
                #else
                ContentView()
                .handlesExternalEvents(preferring: Set(arrayLiteral: "main"), allowing: Set(arrayLiteral: "*"))
                #if os(iOS)
                .task {
                    WidgetSnapshotStore.write(context: Self.sharedModelContainer.mainContext)
                    await IntervalLiveActivityManager.shared.refresh(context: Self.sharedModelContainer.mainContext)
                }
                #endif
                .onAppear {
                    #if os(macOS)
                    MenuBarManager.shared.setup(container: Self.sharedModelContainer)
                    #endif
                }
                #endif
            }
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
