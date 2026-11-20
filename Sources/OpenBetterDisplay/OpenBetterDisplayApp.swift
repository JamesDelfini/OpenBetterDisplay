import AppKit
import OpenBetterDisplayCore
import SwiftUI

@MainActor
private final class VibrantPopoverViewController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>
    private let visualEffectView = NSVisualEffectView()

    init(rootView: Content) {
        self.hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.appearance = NSAppearance(named: .vibrantDark)
        visualEffectView.wantsLayer = true
        self.view = visualEffectView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        hostingController.sizingOptions = [.preferredContentSize]
        addChild(hostingController)

        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor.clear.cgColor

        visualEffectView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            hostedView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])

        updatePreferredContentSize()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updatePreferredContentSize()
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        let size = viewController.preferredContentSize
        if size.width > 0, size.height > 0 {
            preferredContentSize = size
        }
    }

    private func updatePreferredContentSize() {
        let fitted = hostingController.sizeThatFits(
            in: NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        if fitted.width > 0, fitted.height > 0 {
            preferredContentSize = fitted
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private static let builtInBrightnessSyncInterval: TimeInterval = 0.35

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var coordinator: DisplayCoordinator?
    private var reconfigurationObserver: DisplayReconfigurationObserver?
    private var wakeObserver: NSObjectProtocol?
    private var eventMonitor: Any?
    private var brightnessSyncTimer: Timer?

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
        stopPopoverMonitors()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        reconfigurationObserver?.stop()
        reconfigurationObserver = nil
        coordinator?.handleAppWillTerminate()
    }

    func popoverDidClose(_ notification: Notification) {
        handlePopoverClosed()
    }

    private func configurePopover(with coordinator: DisplayCoordinator) {
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        popover.delegate = self
        popover.contentViewController = VibrantPopoverViewController(
            rootView: DisplayPopoverView(coordinator: coordinator)
        )
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

        startPopoverMonitors()
    }

    private func closePopover(_ sender: Any?) {
        popover.performClose(sender)
        handlePopoverClosed()
    }

    private func handlePopoverClosed() {
        stopPopoverMonitors()
        coordinator?.handlePopoverDidClose()
    }

    private func startPopoverMonitors() {
        stopPopoverMonitors()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.closePopover(nil)
        }

        let timer = Timer(
            timeInterval: Self.builtInBrightnessSyncInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown else { return }
                self.coordinator?.syncBuiltInBrightness()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        brightnessSyncTimer = timer
    }

    private func stopPopoverMonitors() {
        brightnessSyncTimer?.invalidate()
        brightnessSyncTimer = nil

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
