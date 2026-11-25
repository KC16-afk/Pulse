import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let monitor = SystemMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: 92)
        guard let button = statusItem.button else { return }
        button.image = MenuBarRenderer.image(for: [0, 0], cpu: 0)
        button.imageScaling = .scaleProportionallyUpOrDown
        button.toolTip = "Pulse — System Monitor"
        button.target = self
        button.action = #selector(togglePopover(_:))

        let rootView = ContentView(monitor: monitor) {
            NSApp.terminate(nil)
        }
        let hostingController = NSHostingController(rootView: rootView)

        popover = NSPopover()
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 520)
        popover.delegate = self

        monitor.onUpdate = { [weak self] snapshot in
            guard let self, let button = self.statusItem.button else { return }
            button.image = MenuBarRenderer.image(for: snapshot.cpuHistory, cpu: snapshot.cpu)
            let memory = snapshot.memoryTotal > 0
                ? Double(snapshot.memoryUsed) / Double(snapshot.memoryTotal) : 0
            button.toolTip = String(
                format: "Pulse  CPU %.0f%%   MEM %.0f%%   Click for details",
                snapshot.cpu * 100, memory * 100
            )
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        popover?.performClose(nil)
    }
}
