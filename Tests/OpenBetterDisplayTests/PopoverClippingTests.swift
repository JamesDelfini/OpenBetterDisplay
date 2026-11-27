import AppKit
import OpenBetterDisplayCore
import OpenBetterDisplayUI
import XCTest

@MainActor
final class PopoverClippingTests: XCTestCase {
    func testPopoverClampsExpandedHeightToScreenLimitAndRemainsScrollableWithoutClipping() {
        let _ = NSApplication.shared

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 1,
                name: "Built-in Display",
                isBuiltIn: true,
                isMain: false,
                currentModeID: 12,
                modes: [
                    RawDisplayMode(
                        modeID: 10,
                        width: 1147,
                        height: 745,
                        pixelWidth: 2294,
                        pixelHeight: 1490,
                        refreshRate: 120,
                        bitsPerSample: 10,
                        isVariableRefreshRate: true,
                        minRefreshRate: 24
                    ),
                    RawDisplayMode(
                        modeID: 11,
                        width: 1352,
                        height: 878,
                        pixelWidth: 2704,
                        pixelHeight: 1756,
                        refreshRate: 120,
                        bitsPerSample: 10,
                        isVariableRefreshRate: true,
                        minRefreshRate: 24
                    ),
                    RawDisplayMode(
                        modeID: 12,
                        width: 1512,
                        height: 982,
                        pixelWidth: 3024,
                        pixelHeight: 1964,
                        refreshRate: 120,
                        isNative: true,
                        bitsPerSample: 10,
                        isDefault: true,
                        isVariableRefreshRate: true,
                        minRefreshRate: 24
                    ),
                    RawDisplayMode(
                        modeID: 13,
                        width: 1800,
                        height: 1169,
                        pixelWidth: 3600,
                        pixelHeight: 2338,
                        refreshRate: 120,
                        bitsPerSample: 10,
                        isVariableRefreshRate: true,
                        minRefreshRate: 24
                    ),
                    RawDisplayMode(
                        modeID: 14,
                        width: 3024,
                        height: 1964,
                        pixelWidth: 3024,
                        pixelHeight: 1964,
                        refreshRate: 120,
                        isNative: true,
                        bitsPerSample: 10,
                        isVariableRefreshRate: true,
                        minRefreshRate: 24
                    )
                ]
            ),
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                currentModeID: 32,
                modes: [
                    RawDisplayMode(
                        modeID: 32,
                        width: 2560,
                        height: 1440,
                        pixelWidth: 5120,
                        pixelHeight: 2880,
                        refreshRate: 120,
                        bitsPerSample: 10
                    ),
                    RawDisplayMode(
                        modeID: 34,
                        width: 3840,
                        height: 2160,
                        pixelWidth: 3840,
                        pixelHeight: 2160,
                        refreshRate: 120,
                        isNative: true,
                        bitsPerSample: 10
                    )
                ]
            ),
            RawDisplayInfo(
                displayID: 20,
                name: "DELL P2217H",
                isBuiltIn: false,
                isMain: false,
                currentModeID: 22,
                modes: [
                    RawDisplayMode(
                        modeID: 22,
                        width: 1920,
                        height: 1080,
                        pixelWidth: 1920,
                        pixelHeight: 1080,
                        refreshRate: 60,
                        isNative: true,
                        bitsPerSample: 8,
                        isDefault: true
                    )
                ]
            )
        ])

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            favoriteModesStore: InMemoryFavoriteModesStore(),
            modeFilterStore: InMemoryDisplayModeFilterStore(),
            hotkeyPreferencesStore: InMemoryHotkeyPreferencesStore()
        )

        let maxHeight: CGFloat = 800
        let controller = VibrantPopoverViewController(
            coordinator: coordinator,
            maxContentHeight: maxHeight
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: maxHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()

        // Collapsed 3-display popover stays compact below maxHeight with no outer scrollbar
        XCTAssertLessThan(controller.preferredContentSize.height, maxHeight)
        XCTAssertGreaterThan(controller.preferredContentSize.height, 600)
        let outerScrollView = findOuterScrollView(in: controller.view)
        XCTAssertNotNil(outerScrollView)
        XCTAssertEqual(outerScrollView?.hasVerticalScroller, false)

        // Expanding Display Mode on Built-in Display (matching temp/testing/clipping.png) clamps to maxHeight
        coordinator.toggleExpandedSection(.displayMode(1))
        pumpMainRunLoop()
        controller.updatePreferredContentSize()
        controller.view.setFrameSize(controller.preferredContentSize)
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.preferredContentSize.height, maxHeight, accuracy: 0.5)
        XCTAssertEqual(outerScrollView?.frame.height ?? 0, maxHeight, accuracy: 0.5)
        XCTAssertEqual(outerScrollView?.hasVerticalScroller, true)
        XCTAssertEqual(outerScrollView?.contentView.isFlipped, true)
        XCTAssertEqual(outerScrollView?.contentView.bounds.origin.y ?? -1, 0, accuracy: 0.5)

        if let documentView = outerScrollView?.documentView {
            XCTAssertGreaterThan(documentView.frame.height, 1000)
            XCTAssertEqual(documentView.frame.minY, 0, accuracy: 0.5)
        } else {
            XCTFail("Expected scrollView documentView")
        }

        // Scroll down toward footer, then collapse back -> viewport shrinks cleanly and resets scroll bounds
        outerScrollView?.contentView.scroll(to: NSPoint(x: 0, y: 200))
        outerScrollView?.reflectScrolledClipView(outerScrollView!.contentView)

        coordinator.toggleExpandedSection(.displayMode(1))
        pumpMainRunLoop()
        controller.updatePreferredContentSize()
        controller.view.setFrameSize(controller.preferredContentSize)
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertLessThan(controller.preferredContentSize.height, maxHeight)
        XCTAssertEqual(outerScrollView?.hasVerticalScroller, false)
        XCTAssertEqual(outerScrollView?.contentView.bounds.origin.y ?? -1, 0, accuracy: 0.5)
    }

    func testPopoverLayoutMetricsComputesAvailableHeightBelowMenuBarAnchor() {
        let screenVisible = CGRect(x: 0, y: 70, width: 1512, height: 880)
        let statusButton = CGRect(x: 1100, y: 950, width: 28, height: 32)
        let height = PopoverLayoutMetrics.maxContentHeight(
            anchorRectInScreen: statusButton,
            screenVisibleFrame: screenVisible
        )
        XCTAssertEqual(height, 844)

        let tinyScreen = CGRect(x: 0, y: 0, width: 800, height: 220)
        XCTAssertEqual(
            PopoverLayoutMetrics.maxContentHeight(anchorRectInScreen: nil, screenVisibleFrame: tinyScreen),
            PopoverLayoutMetrics.minimumContentHeight
        )
    }

    private func findOuterScrollView(in view: NSView) -> NSScrollView? {
        var queue = view.subviews
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let scrollView = current as? NSScrollView {
                return scrollView
            }
            queue.append(contentsOf: current.subviews)
        }
        return nil
    }

    private func pumpMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
