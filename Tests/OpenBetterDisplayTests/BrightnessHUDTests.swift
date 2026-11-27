import AppKit
import CoreGraphics
import OpenBetterDisplayCore
import OpenBetterDisplayUI
import XCTest

@MainActor
private final class ManualHUDTimerScheduler: BrightnessHUDTimerScheduling {
    final class Token: BrightnessHUDTimerCancellable {
        let fireTime: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false

        init(fireTime: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.fireTime = fireTime
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }
    }

    var currentTime: TimeInterval = 0
    var tokens: [Token] = []

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> BrightnessHUDTimerCancellable {
        let token = Token(fireTime: currentTime + max(0, delay), action: action)
        tokens.append(token)
        return token
    }

    func advance(by interval: TimeInterval) {
        currentTime += interval
        while let next = tokens.filter({ !$0.isCancelled && $0.fireTime <= currentTime + 1e-9 }).min(by: { $0.fireTime < $1.fireTime }) {
            tokens.removeAll { $0 === next }
            next.action()
        }
    }
}

@MainActor
final class BrightnessHUDTests: XCTestCase {
    func testShowBrightnessHUDCreatesNonActivatingClickThroughPanelCenteredNearVisibleBottomAndDismissesOnQuit() {
        let _ = NSApplication.shared
        let scheduler = ManualHUDTimerScheduler()
        let visibleFrames: [UInt32: CGRect] = [
            20: CGRect(x: 2560, y: 360, width: 1920, height: 1080)
        ]
        let controller = BrightnessHUDPanelController(
            displayDuration: 1.2,
            fadeOutDuration: 0,
            bottomMargin: 72,
            screenVisibleFrameProvider: { visibleFrames[$0] },
            timerScheduler: scheduler
        )

        let update = BrightnessHUDUpdate(
            displayID: 20,
            displayName: "DELL P2217H",
            symbolName: "display",
            brightness: 0.75,
            brightnessPercentage: 75,
            backend: .hardwareDDC
        )
        controller.showBrightnessHUD([update])

        guard let panel = controller.activePanelsByDisplayID[20] else {
            XCTFail("Expected an active Brightness HUD panel for display 20")
            return
        }

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertEqual(panel.level, .statusBar)
        XCTAssertTrue(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]))
        XCTAssertEqual(panel.alphaValue, 1.0, accuracy: 0.001)
        XCTAssertEqual(panel.frame.width, BrightnessHUDView.preferredWidth, accuracy: 1.0)
        XCTAssertGreaterThan(panel.frame.height, 40.0)
        XCTAssertEqual(controller.displayedUpdate(for: 20), update)

        // Centered horizontally in visibleFrame (2560 + 1920/2 = 3520), 72pt above visibleFrame.minY (360 + 72 = 432)
        XCTAssertEqual(panel.frame.midX, 3520, accuracy: 1.0)
        XCTAssertEqual(panel.frame.minY, 432, accuracy: 1.0)

        // Still visible before 1.2s elapses, then dismissed once 1.2s completes
        scheduler.advance(by: 1.1)
        XCTAssertNotNil(controller.activePanelsByDisplayID[20])
        scheduler.advance(by: 0.15)
        XCTAssertNil(controller.activePanelsByDisplayID[20])

        // Re-show then verify quit teardown closes immediately
        controller.showBrightnessHUD([update])
        XCTAssertNotNil(controller.activePanelsByDisplayID[20])
        controller.dismissAllBrightnessHUDs()
        XCTAssertTrue(controller.activePanelsByDisplayID.isEmpty)
    }

    func testRepeatedAndHeldUpdatesResetAutoFadeTimerAndUpdateMultiDisplayHUDsIndependently() {
        let _ = NSApplication.shared
        let scheduler = ManualHUDTimerScheduler()
        var visibleFrames: [UInt32: CGRect] = [
            20: CGRect(x: 2560, y: 360, width: 1920, height: 1080),
            30: CGRect(x: 0, y: 0, width: 2560, height: 1410)
        ]
        let controller = BrightnessHUDPanelController(
            displayDuration: 1.2,
            fadeOutDuration: 0,
            bottomMargin: 72,
            screenVisibleFrameProvider: { visibleFrames[$0] },
            timerScheduler: scheduler
        )
        let gateway = MacOSBrightnessHotkeyGateway(hudPresenter: controller)
        defer { gateway.stop() }

        let initialUpdates = [
            BrightnessHUDUpdate(
                displayID: 20,
                displayName: "DELL P2217H",
                symbolName: "display",
                brightness: 0.50,
                brightnessPercentage: 50,
                backend: .hardwareDDC
            ),
            BrightnessHUDUpdate(
                displayID: 30,
                displayName: "DELL U2725QE",
                symbolName: "display",
                brightness: 0.80,
                brightnessPercentage: 80,
                backend: .softwareGamma
            )
        ]
        gateway.showBrightnessHUD(initialUpdates)

        guard let panel20 = controller.activePanelsByDisplayID[20],
            let panel30 = controller.activePanelsByDisplayID[30]
        else {
            XCTFail("Expected panels for both external displays")
            return
        }
        XCTAssertFalse(panel20 === panel30)
        XCTAssertEqual(panel20.frame.midX, 3520, accuracy: 1.0)
        XCTAssertEqual(panel20.frame.minY, 432, accuracy: 1.0)
        XCTAssertEqual(panel30.frame.midX, 1280, accuracy: 1.0)
        XCTAssertEqual(panel30.frame.minY, 72, accuracy: 1.0)

        // Advance 0.9s (before 1.2s expiry), then hold-repeat on display 20 only -> timer resets for display 20
        scheduler.advance(by: 0.9)
        let repeatUpdate20 = BrightnessHUDUpdate(
            displayID: 20,
            displayName: "DELL P2217H",
            symbolName: "display",
            brightness: 0.5625,
            brightnessPercentage: 56,
            backend: .hardwareDDC
        )
        gateway.showBrightnessHUD([repeatUpdate20])
        XCTAssertEqual(controller.displayedUpdate(for: 20), repeatUpdate20)

        // Advance 0.4s (total 1.3s since initial press): display 30 expires, display 20 remains visible (0.4s since repeat)
        scheduler.advance(by: 0.4)
        XCTAssertNil(controller.activePanelsByDisplayID[30])
        XCTAssertNotNil(controller.activePanelsByDisplayID[20])

        // Advance another 0.7s (1.1s since repeat): display 20 is still visible
        scheduler.advance(by: 0.7)
        XCTAssertNotNil(controller.activePanelsByDisplayID[20])

        // Advance 0.15s (1.25s since repeat): display 20 dismisses cleanly
        scheduler.advance(by: 0.15)
        XCTAssertNil(controller.activePanelsByDisplayID[20])

        // Screen missing or disconnected during presentation does not crash and cleans up orphaned panel
        gateway.showBrightnessHUD(initialUpdates)
        XCTAssertEqual(Set(controller.activePanelsByDisplayID.keys), [20, 30])
        visibleFrames.removeValue(forKey: 20)
        controller.reconcileVisibleScreens()
        XCTAssertEqual(Set(controller.activePanelsByDisplayID.keys), [30])

        // Presenting for a displayID with no matching NSScreen skips cleanly
        gateway.showBrightnessHUD([
            BrightnessHUDUpdate(
                displayID: 999,
                displayName: "Missing Display",
                symbolName: "display",
                brightness: 0.5,
                brightnessPercentage: 50,
                backend: .hardwareDDC
            )
        ])
        XCTAssertNil(controller.activePanelsByDisplayID[999])

        // Gateway stop tears down remaining panels cleanly on quit
        gateway.stop()
        XCTAssertTrue(controller.activePanelsByDisplayID.isEmpty)
    }

    func testPanelOriginClampsWithinSmallVisibleFrameAndRespectsDockInset() {
        let standardOrigin = BrightnessHUDLayout.panelOrigin(
            in: CGRect(x: 0, y: 78, width: 2560, height: 1332),
            panelSize: CGSize(width: 264, height: 68),
            bottomMargin: 72
        )
        XCTAssertEqual(standardOrigin.x, 1148, accuracy: 0.5)
        XCTAssertEqual(standardOrigin.y, 150, accuracy: 0.5)

        let clampedOrigin = BrightnessHUDLayout.panelOrigin(
            in: CGRect(x: 100, y: 50, width: 200, height: 90),
            panelSize: CGSize(width: 264, height: 68),
            bottomMargin: 72
        )
        XCTAssertEqual(clampedOrigin.x, 100, accuracy: 0.5)
        XCTAssertEqual(clampedOrigin.y, 72, accuracy: 0.5)
    }

    func testAnimatedFadeOutInterruptionRestoresFullOpacityWithoutDismissing() {
        let _ = NSApplication.shared
        let scheduler = ManualHUDTimerScheduler()
        let visibleFrames: [UInt32: CGRect] = [
            30: CGRect(x: 0, y: 0, width: 2560, height: 1410)
        ]
        let controller = BrightnessHUDPanelController(
            displayDuration: 1.2,
            fadeOutDuration: 0.15,
            bottomMargin: 72,
            screenVisibleFrameProvider: { visibleFrames[$0] },
            timerScheduler: scheduler
        )
        defer { controller.dismissAllBrightnessHUDs() }

        let first = BrightnessHUDUpdate(
            displayID: 30,
            displayName: "DELL U2725QE",
            symbolName: "display",
            brightness: 0.50,
            brightnessPercentage: 50,
            backend: .hardwareDDC
        )
        controller.showBrightnessHUD([first])

        // Trigger animated fade-out at 1.2s, then interrupt immediately with a fresh press
        scheduler.advance(by: 1.2)
        let second = BrightnessHUDUpdate(
            displayID: 30,
            displayName: "DELL U2725QE",
            symbolName: "display",
            brightness: 0.5625,
            brightnessPercentage: 56,
            backend: .hardwareDDC
        )
        controller.showBrightnessHUD([second])

        // Allow any in-flight NSAnimationContext completion from the interrupted fade-out to drain
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))

        guard let panel = controller.activePanelsByDisplayID[30] else {
            XCTFail("Interrupted fade-out must keep HUD panel active")
            return
        }
        XCTAssertEqual(panel.alphaValue, 1.0, accuracy: 0.001)
        XCTAssertEqual(controller.displayedUpdate(for: 30), second)
    }
}
