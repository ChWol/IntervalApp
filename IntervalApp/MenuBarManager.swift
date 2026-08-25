import SwiftUI
import SwiftData

#if os(macOS)
import AppKit

final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var timer: Timer?
    private var modelContainer: ModelContainer?
    
    func setup(container: ModelContainer) {
        self.modelContainer = container
        updateStatusItem()
        
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem()
        }
    }
    
    func updateStatusItem() {
        let isEnabled = UserDefaults.standard.object(forKey: "showMenuBarExtra") != nil
            ? UserDefaults.standard.bool(forKey: "showMenuBarExtra")
            : true
        
        if isEnabled {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    button.target = self
                    button.action = #selector(togglePopover(_:))
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                }
                
                if let container = modelContainer {
                    let hostingController = NSHostingController(
                        rootView: MenuBarTaskView()
                            .modelContainer(container)
                    )
                    popover.contentSize = NSSize(width: 300, height: 380)
                    popover.behavior = .transient
                    popover.contentViewController = hostingController
                }
                
                self.statusItem = item
                startTimer()
                updateButtonTitle()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateButtonTitle()
        }
    }
    
    private func updateButtonTitle() {
        guard let button = statusItem?.button else { return }
        let now = Date()
        let minute = Calendar.current.component(.minute, from: now)
        let remaining = max(0, 60 - minute)
        
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        let img = NSImage(systemSymbolName: "clock", accessibilityDescription: "Interval")?.withSymbolConfiguration(config)
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        button.title = " \(remaining)m"
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .light)
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Update root view before showing to ensure fresh context
            if let container = modelContainer {
                popover.contentViewController = NSHostingController(
                    rootView: MenuBarTaskView()
                        .modelContainer(container)
                )
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
#endif
