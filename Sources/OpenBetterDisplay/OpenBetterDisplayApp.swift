import AppKit
import OpenBetterDisplayCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var coordinator: DisplayCoordinator?
    private var reconfigurationObserver: DisplayReconfigurationObserver?
    private var wakeObserver: NSObjectProtocol?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let driver = MacOSDisplayDriver()
        let coordinator = DisplayCoordinator(driver: driver)
        self.coordinator = coordinator

        self.reconfigurationObserver = DisplayReconfigurationObserver { [weak self] in
            self?.coordinator?.handleDisplayReconfiguration()
        }

        self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.coordinator?.handleSystemWake()
            }
        }

        configurePopover(with: coordinator)
        configureStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        reconfigurationObserver?.stop()
        reconfigurationObserver = nil
        coordinator?.handleAppWillTerminate()
    }

    private func configurePopover(with coordinator: DisplayCoordinator) {
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        let hostingController = NSHostingController(
            rootView: DisplayPopoverView(coordinator: coordinator)
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "display",
                accessibilityDescription: "OpenBetterDisplay"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "OpenBetterDisplay"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        self.statusItem = item
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        coordinator?.refreshDisplays()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.closePopover(nil)
        }
    }

    private func closePopover(_ sender: Any?) {
        popover.performClose(sender)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

@main
struct OpenBetterDisplayMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
