import AppKit
import CoreGraphics
import Foundation
import OpenBetterDisplayCore
import SwiftUI

@MainActor
public protocol BrightnessHUDTimerCancellable: AnyObject {
    func cancel()
}

@MainActor
public protocol BrightnessHUDTimerScheduling: AnyObject {
    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> BrightnessHUDTimerCancellable
}

@MainActor
public final class RunLoopBrightnessHUDTimerScheduler: BrightnessHUDTimerScheduling {
    private final class TimerToken: BrightnessHUDTimerCancellable {
        private var timer: Timer?

        init(timer: Timer) {
            self.timer = timer
        }

        func cancel() {
            timer?.invalidate()
            timer = nil
        }
    }

    public init() {}

    public func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> BrightnessHUDTimerCancellable {
        let timer = Timer(timeInterval: max(0, delay), repeats: false) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return TimerToken(timer: timer)
    }
}

/// Computes bottom-center Brightness HUD origins clamped inside a screen's visible frame.
public enum BrightnessHUDLayout {
    public static let defaultBottomMargin: CGFloat = 72
    public static let fallbackPanelSize = CGSize(width: BrightnessHUDView.preferredWidth, height: 68)

    public static func panelOrigin(
        in visibleFrame: CGRect,
        panelSize: CGSize,
        bottomMargin: CGFloat = defaultBottomMargin
    ) -> CGPoint {
        let minX = visibleFrame.minX
        let maxX = max(minX, visibleFrame.maxX - panelSize.width)
        let centeredX = visibleFrame.midX - panelSize.width / 2.0
        let clampedX = min(max(centeredX, minX), maxX)

        let minY = visibleFrame.minY
        let maxY = max(minY, visibleFrame.maxY - panelSize.height)
        let preferredY = visibleFrame.minY + bottomMargin
        let clampedY = min(max(preferredY, minY), maxY)

        return CGPoint(x: clampedX, y: clampedY)
    }
}

private final class NonActivatingBrightnessHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class BrightnessHUDState: ObservableObject {
    @Published var update: BrightnessHUDUpdate

    init(update: BrightnessHUDUpdate) {
        self.update = update
    }
}

private struct BrightnessHUDContainerView: View {
    @ObservedObject var state: BrightnessHUDState

    var body: some View {
        BrightnessHUDView(update: state.update)
    }
}

/// Manages non-activating, click-through floating Brightness HUD panels per adjusted external Target Display.
@MainActor
public final class BrightnessHUDPanelController: BrightnessHUDPresenting {
    private struct HUDEntry {
        let panel: NonActivatingBrightnessHUDPanel
        let hostingView: NSHostingView<BrightnessHUDContainerView>
        let state: BrightnessHUDState
        var fadeTimer: BrightnessHUDTimerCancellable?
        var generation: UInt64 = 0
    }

    nonisolated public static let defaultDisplayDuration: TimeInterval = 1.2
    nonisolated public static let defaultFadeOutDuration: TimeInterval = 0.25

    private let displayDuration: TimeInterval
    private let fadeOutDuration: TimeInterval
    private let bottomMargin: CGFloat
    private let screenVisibleFrameProvider: (UInt32) -> CGRect?
    private let timerScheduler: BrightnessHUDTimerScheduling
    private var entries: [UInt32: HUDEntry] = [:]
    private nonisolated(unsafe) var screenParametersObserver: NSObjectProtocol?

    public var activePanelsByDisplayID: [UInt32: NSPanel] {
        entries.mapValues(\.panel)
    }

    public init(
        displayDuration: TimeInterval = BrightnessHUDPanelController.defaultDisplayDuration,
        fadeOutDuration: TimeInterval = BrightnessHUDPanelController.defaultFadeOutDuration,
        bottomMargin: CGFloat = BrightnessHUDLayout.defaultBottomMargin,
        screenVisibleFrameProvider: ((UInt32) -> CGRect?)? = nil,
        timerScheduler: BrightnessHUDTimerScheduling? = nil
    ) {
        self.displayDuration = max(0, displayDuration)
        self.fadeOutDuration = max(0, fadeOutDuration)
        self.bottomMargin = max(0, bottomMargin)
        self.screenVisibleFrameProvider = screenVisibleFrameProvider ?? Self.defaultVisibleFrame(for:)
        self.timerScheduler = timerScheduler ?? RunLoopBrightnessHUDTimerScheduler()
        startObservingScreenChanges()
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
    }

    public func displayedUpdate(for displayID: UInt32) -> BrightnessHUDUpdate? {
        entries[displayID]?.state.update
    }

    public func showBrightnessHUD(_ updates: [BrightnessHUDUpdate]) {
        for update in updates {
            presentOrRefreshHUD(for: update)
        }
    }

    public func dismissAllBrightnessHUDs() {
        let currentEntries = Array(entries.values)
        entries.removeAll()
        for var entry in currentEntries {
            entry.generation &+= 1
            entry.fadeTimer?.cancel()
            entry.fadeTimer = nil
            entry.panel.orderOut(nil)
            entry.panel.close()
        }
    }

    public func reconcileVisibleScreens() {
        let displayIDs = Array(entries.keys)
        for displayID in displayIDs {
            guard let visibleFrame = screenVisibleFrameProvider(displayID) else {
                dismissEntry(for: displayID)
                continue
            }
            if let entry = entries[displayID] {
                position(entry: entry, in: visibleFrame)
            }
        }
    }

    private func presentOrRefreshHUD(for update: BrightnessHUDUpdate) {
        guard let visibleFrame = screenVisibleFrameProvider(update.displayID) else {
            dismissEntry(for: update.displayID)
            return
        }

        var entry = entries[update.displayID] ?? makeEntry(for: update)
        entry.generation &+= 1
        entry.fadeTimer?.cancel()
        entry.fadeTimer = nil
        entry.state.update = update

        // Reset any in-flight fade animation immediately on repeated/held presses.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            entry.panel.animator().alphaValue = 1.0
        }
        entry.panel.alphaValue = 1.0

        position(entry: entry, in: visibleFrame)
        entry.panel.orderFrontRegardless()

        let expectedGeneration = entry.generation
        let displayID = update.displayID
        entry.fadeTimer = timerScheduler.schedule(after: displayDuration) { [weak self] in
            self?.beginFadeOut(for: displayID, expectedGeneration: expectedGeneration)
        }
        entries[displayID] = entry
    }

    private func makeEntry(for update: BrightnessHUDUpdate) -> HUDEntry {
        let state = BrightnessHUDState(update: update)
        let hostingView = NSHostingView(rootView: BrightnessHUDContainerView(state: state))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.appearance = NSAppearance(named: .vibrantDark)
        visualEffectView.maskImage = Self.makeRoundedMaskImage(cornerRadius: BrightnessHUDView.cornerRadius)
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = BrightnessHUDView.cornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])

        let panel = NonActivatingBrightnessHUDPanel(
            contentRect: CGRect(origin: .zero, size: BrightnessHUDLayout.fallbackPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.appearance = NSAppearance(named: .vibrantDark)
        panel.contentView = visualEffectView

        return HUDEntry(panel: panel, hostingView: hostingView, state: state)
    }

    private func position(entry: HUDEntry, in visibleFrame: CGRect) {
        entry.hostingView.layoutSubtreeIfNeeded()
        let fitted = entry.hostingView.fittingSize
        let panelSize =
            (fitted.width > 0 && fitted.height > 0)
            ? fitted
            : BrightnessHUDLayout.fallbackPanelSize
        let origin = BrightnessHUDLayout.panelOrigin(
            in: visibleFrame,
            panelSize: panelSize,
            bottomMargin: bottomMargin
        )
        entry.panel.setFrame(CGRect(origin: origin, size: panelSize), display: true)
    }

    private func beginFadeOut(for displayID: UInt32, expectedGeneration: UInt64) {
        guard var entry = entries[displayID], entry.generation == expectedGeneration else {
            return
        }
        entry.fadeTimer = nil
        entries[displayID] = entry

        guard fadeOutDuration > 0 else {
            dismissEntry(for: displayID)
            return
        }

        let duration = fadeOutDuration
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = duration
                entry.panel.animator().alphaValue = 0.0
            },
            completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.finishFadeOut(for: displayID, expectedGeneration: expectedGeneration)
                }
            }
        )
    }

    private func finishFadeOut(for displayID: UInt32, expectedGeneration: UInt64) {
        guard let entry = entries[displayID], entry.generation == expectedGeneration else {
            return
        }
        dismissEntry(for: displayID)
    }

    private func dismissEntry(for displayID: UInt32) {
        guard var entry = entries.removeValue(forKey: displayID) else {
            return
        }
        entry.generation &+= 1
        entry.fadeTimer?.cancel()
        entry.fadeTimer = nil
        entry.panel.orderOut(nil)
        entry.panel.close()
    }

    private func startObservingScreenChanges() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reconcileVisibleScreens()
            }
        }
    }

    private static func defaultVisibleFrame(for displayID: UInt32) -> CGRect? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first(where: { screen in
            (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value == displayID
        })?.visibleFrame
    }

    private static func makeRoundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 2
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }
}
