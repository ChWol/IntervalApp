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
    
    private var isSetup = false
    
    func setup(container: ModelContainer) {
        self.modelContainer = container
        if !isSetup {
            isSetup = true
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateStatusItem()
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItem()
        }
    }
    
    func updateStatusItem() {
        assert(Thread.isMainThread, "updateStatusItem must be called on main thread")
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
    
    private static func createIntervalLogoImage() -> NSImage {
        let size = NSSize(width: 15, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            // 5 vertical Interval bars of decreasing widths
            let bars: [(x: CGFloat, w: CGFloat)] = [
                (0.0, 4.5),
                (5.5, 3.0),
                (9.5, 1.8),
                (12.1, 1.1),
                (13.9, 0.8)
            ]
            NSColor.black.setFill()
            for bar in bars {
                let barRect = NSRect(x: bar.x, y: 0.5, width: bar.w, height: rect.height - 1.0)
                let path = NSBezierPath(roundedRect: barRect, xRadius: 0.3, yRadius: 0.3)
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
    
    private func updateButtonTitle() {
        guard let button = statusItem?.button else { return }
        let now = Date()
        let minute = Calendar.current.component(.minute, from: now)
        let remaining = max(0, 60 - minute)
        
        button.image = Self.createIntervalLogoImage()
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
