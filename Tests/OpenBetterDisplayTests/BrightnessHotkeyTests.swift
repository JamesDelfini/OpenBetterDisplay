import CoreGraphics
import XCTest

@testable import OpenBetterDisplayCore

@MainActor
final class BrightnessHotkeyTests: XCTestCase {
    func testFollowMouseCursorTargetsEnabledDisplayUnderPointerAndFallsBackToMainDisplay() {
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(
                    displayID: 1,
                    name: "Built-in Display",
                    isBuiltIn: true,
                    isMain: false,
                    bounds: CGRect(x: -1512, y: 0, width: 1512, height: 982)
                ),
                RawDisplayInfo(
                    displayID: 20,
                    name: "DELL P2217H",
                    isBuiltIn: false,
                    isMain: false,
                    bounds: CGRect(x: 2560, y: 0, width: 1920, height: 1080)
                ),
                RawDisplayInfo(
                    displayID: 30,
                    name: "DELL U2725QE",
                    isBuiltIn: false,
                    isMain: true,
                    bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440)
                )
            ],
            brightnessReadings: [
                1: BrightnessReading(level: 0.50, backend: .nativeAppleBacklight),
                20: BrightnessReading(level: 0.80, backend: .hardwareDDC),
                30: BrightnessReading(level: 0.60, backend: .hardwareDDC)
            ]
        )
        let gateway = FakeBrightnessHotkeyGateway()
        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0,
            writeScheduler: ImmediateBrightnessWriteScheduler(),
            hotkeyGateway: gateway,
            hotkeyPreferencesStore: InMemoryHotkeyPreferencesStore()
        )

        XCTAssertEqual(coordinator.hotkeyPreferences.targetMode, .followMouseCursor)
        XCTAssertTrue(coordinator.hotkeyPreferences.isMediaKeysEnabled)
        XCTAssertFalse(coordinator.hotkeyPreferences.isLiteralF1F2Enabled)

        // Pointer over external DELL P2217H -> consumed (true), decreases by 1/16 (0.0625)
        let consumedP2217H = gateway.simulateKeyEvent(
            BrightnessKeyEvent(
                direction: .decrease,
                source: .mediaBrightness,
                isFine: false,
                pointerLocation: CGPoint(x: 3000, y: 500)
            )
        )
        XCTAssertTrue(consumedP2217H)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 20 })?.brightness ?? -1, 0.7375, accuracy: 0.0001)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.brightness ?? -1, 0.60, accuracy: 0.0001)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 1 })?.brightness ?? -1, 0.50, accuracy: 0.0001)

        // Pointer over Built-in Display -> passed through to macOS (false), Core does not modify brightness
        driver.setBrightnessHistory.removeAll()
        let consumedBuiltIn = gateway.simulateKeyEvent(
            BrightnessKeyEvent(
                direction: .increase,
                source: .mediaBrightness,
                isFine: false,
                pointerLocation: CGPoint(x: -500, y: 400)
            )
        )
        XCTAssertFalse(consumedBuiltIn)
        XCTAssertTrue(driver.setBrightnessHistory.isEmpty)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 1 })?.brightness ?? -1, 0.50, accuracy: 0.0001)

        // Pointer outside any display bounds -> falls back to Main Display (DELL U2725QE, external -> consumed)
        let consumedFallback = gateway.simulateKeyEvent(
            BrightnessKeyEvent(
                direction: .increase,
                source: .mediaBrightness,
                isFine: false,
                pointerLocation: CGPoint(x: 9999, y: 9999)
            )
        )
        XCTAssertTrue(consumedFallback)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.brightness ?? -1, 0.6625, accuracy: 0.0001)

        // Disconnect DELL P2217H; pointer over its old bounds must ignore Disconnected Display and fall back to Main Display
        coordinator.setDisplayEnabled(20, enabled: false)
        let consumedOverDisconnected = gateway.simulateKeyEvent(
            BrightnessKeyEvent(
                direction: .decrease,
                source: .mediaBrightness,
                isFine: false,
                pointerLocation: CGPoint(x: 3000, y: 500)
            )
        )
        XCTAssertTrue(consumedOverDisconnected)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 20 })?.brightness ?? -1, 0.7375, accuracy: 0.0001)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.brightness ?? -1, 0.60, accuracy: 0.0001)
    }

    func testAllEnabledDisplaysAndMainDisplayTargetModesFineStepAndBuiltInPassthrough() {
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(
                    displayID: 1,
                    name: "Built-in Display",
                    isBuiltIn: true,
                    isMain: false,
                    bounds: CGRect(x: -1512, y: 0, width: 1512, height: 982)
                ),
                RawDisplayInfo(
                    displayID: 20,
                    name: "DELL P2217H",
                    isBuiltIn: false,
                    isMain: false,
                    bounds: CGRect(x: 2560, y: 0, width: 1920, height: 1080)
                ),
                RawDisplayInfo(
                    displayID: 30,
                    name: "DELL U2725QE",
                    isBuiltIn: false,
                    isMain: true,
                    bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440)
                )
            ],
            brightnessReadings: [
                1: BrightnessReading(level: 0.20, backend: .nativeAppleBacklight),
                20: BrightnessReading(level: 0.96, backend: .hardwareDDC),
                30: BrightnessReading(level: 0.03, backend: .hardwareDDC)
            ]
        )
        let gateway = FakeBrightnessHotkeyGateway(pointerLocation: CGPoint(x: 3000, y: 500))
        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0,
            writeScheduler: ImmediateBrightnessWriteScheduler(),
            hotkeyGateway: gateway,
            hotkeyPreferencesStore: InMemoryHotkeyPreferencesStore()
        )

        // Fine step (1/64 = 0.015625) using gateway's pointerLocation when event.pointerLocation is nil
        XCTAssertTrue(
            gateway.simulateKeyEvent(
                BrightnessKeyEvent(direction: .decrease, source: .mediaBrightness, isFine: true, isRepeat: true)
            )
        )
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 20 })?.brightness ?? -1, 0.944375, accuracy: 0.0001)

        // Switch to All Enabled Displays -> independent relative stepping + clamping to [0, 1]
        coordinator.setHotkeyTargetMode(.allEnabledDisplays)
        XCTAssertEqual(coordinator.hotkeyPreferences.targetMode, .allEnabledDisplays)
        XCTAssertTrue(
            gateway.simulateKeyEvent(
                BrightnessKeyEvent(direction: .increase, source: .mediaBrightness, isFine: false)
            )
        )
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 1 })?.brightness ?? -1, 0.2625, accuracy: 0.0001)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 20 })?.brightness ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.brightness ?? -1, 0.0925, accuracy: 0.0001)

        // Disconnect display 20 and fine-decrease -> disconnected display 20 stays untouched at 1.0, display 30 clamps to 0.0
        coordinator.setDisplayEnabled(20, enabled: false)
        XCTAssertTrue(
            gateway.simulateKeyEvent(
                BrightnessKeyEvent(direction: .decrease, source: .mediaBrightness, isFine: false)
            )
        )
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 1 })?.brightness ?? -1, 0.20, accuracy: 0.0001)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 20 })?.brightness ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.brightness ?? -1, 0.03, accuracy: 0.0001)

        // Main Display mode ignores pointerLocation over display 20 (re-enabled) and targets Main Display (30)
        coordinator.setDisplayEnabled(20, enabled: true)
        coordinator.setHotkeyTargetMode(.mainDisplay)
        XCTAssertTrue(
            gateway.simulateKeyEvent(
                BrightnessKeyEvent(
                    direction: .decrease,
                    source: .mediaBrightness,
                    isFine: false,
                    pointerLocation: CGPoint(x: 3000, y: 500)
                )
            )
        )
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 20 })?.brightness ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.brightness ?? -1, 0.0, accuracy: 0.0001)

        // When Built-in Display is Main Display in .mainDisplay mode (or sole enabled display in .allEnabledDisplays),
        // media brightness keys pass through (false)
        coordinator.setMainDisplay(1)
        driver.setBrightnessHistory.removeAll()
        XCTAssertFalse(
            gateway.simulateKeyEvent(
                BrightnessKeyEvent(direction: .increase, source: .mediaBrightness, isFine: false)
            )
        )
        XCTAssertTrue(driver.setBrightnessHistory.isEmpty)

        coordinator.setHotkeyTargetMode(.allEnabledDisplays)
        coordinator.setDisplayEnabled(20, enabled: false)
        coordinator.setDisplayEnabled(30, enabled: false)
        XCTAssertFalse(
            gateway.simulateKeyEvent(
                BrightnessKeyEvent(direction: .increase, source: .mediaBrightness, isFine: false)
            )
        )
        XCTAssertTrue(driver.setBrightnessHistory.isEmpty)
    }

    func testLiteralF1F2ToggleMediaTogglePersistenceHUDUpdatesAndTerminationStop() {
        let store = InMemoryHotkeyPreferencesStore()
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(
                    displayID: 1,
                    name: "Built-in Display",
                    isBuiltIn: true,
                    isMain: false,
                    bounds: CGRect(x: -1512, y: 0, width: 1512, height: 982)
                ),
                RawDisplayInfo(
                    displayID: 20,
                    name: "DELL P2217H",
                    isBuiltIn: false,
                    isMain: false,
                    bounds: CGRect(x: 2560, y: 0, width: 1920, height: 1080)
                ),
                RawDisplayInfo(
                    displayID: 30,
                    name: "DELL U2725QE",
                    isBuiltIn: false,
                    isMain: true,
                    bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440)
                )
            ],
            brightnessReadings: [
                1: BrightnessReading(level: 0.50, backend: .nativeAppleBacklight),
                20: BrightnessReading(level: 0.80, backend: .hardwareDDC),
                30: BrightnessReading(level: 0.60, backend: .softwareGamma)
            ],
            unsupportedDDCDisplayIDs: [30]
        )
        let gateway = FakeBrightnessHotkeyGateway()
        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0,
            writeScheduler: ImmediateBrightnessWriteScheduler(),
            hotkeyGateway: gateway,
            hotkeyPreferencesStore: store
        )

        var emittedHUDBatches: [[BrightnessHUDUpdate]] = []
        coordinator.onBrightnessHUDUpdate = { updates in
            emittedHUDBatches.append(updates)
        }

        // Literal F1/F2 is opt-in and disabled by default
        XCTAssertFalse(
            gateway.simulateKeyEvent(
                BrightnessKeyEvent(
                    direction: .decrease,
                    source: .literalFunctionKey,
                    pointerLocation: CGPoint(x: 3000, y: 500)
                )
            )
        )
        XCTAssertTrue(emittedHUDBatches.isEmpty)

        // Enable literal F1/F2 -> gateway receives updated preferences
        coordinator.setLiteralF1F2Enabled(true)
        XCTAssertTrue(coordinator.hotkeyPreferences.isLiteralF1F2Enabled)
        XCTAssertEqual(gateway.appliedPreferencesHistory.last?.isLiteralF1F2Enabled, true)

        // Literal F1 over Built-in Display adjusts Built-in backlight and consumes, without emitting external HUD update
        XCTAssertTrue(
            gateway.simulateKeyEvent(
                BrightnessKeyEvent(
                    direction: .decrease,
                    source: .literalFunctionKey,
                    pointerLocation: CGPoint(x: -400, y: 400)
                )
            )
        )
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 1 })?.brightness ?? -1, 0.4375, accuracy: 0.0001)
        XCTAssertTrue(emittedHUDBatches.isEmpty)

        // All Enabled Displays + literal F2 emits HUD updates ONLY for external displays (20 and 30)
        coordinator.setHotkeyTargetMode(.allEnabledDisplays)
        XCTAssertTrue(
            gateway.simulateKeyEvent(
                BrightnessKeyEvent(direction: .increase, source: .literalFunctionKey)
            )
        )
        XCTAssertEqual(
            emittedHUDBatches.last,
            [
                BrightnessHUDUpdate(
                    displayID: 20,
                    displayName: "DELL P2217H",
                    symbolName: "display",
                    brightness: 0.8625,
                    brightnessPercentage: 86,
                    backend: .hardwareDDC
                ),
                BrightnessHUDUpdate(
                    displayID: 30,
                    displayName: "DELL U2725QE",
                    symbolName: "display",
                    brightness: 0.6625,
                    brightnessPercentage: 66,
                    backend: .softwareGamma
                )
            ]
        )
        XCTAssertEqual(coordinator.lastBrightnessHUDUpdates, emittedHUDBatches.last)

        // Disabling Brightness Media Keys prevents media key interception even over external monitors
        coordinator.setMediaKeysEnabled(false)
        XCTAssertFalse(coordinator.hotkeyPreferences.isMediaKeysEnabled)
        XCTAssertFalse(
            gateway.simulateKeyEvent(
                BrightnessKeyEvent(direction: .decrease, source: .mediaBrightness)
            )
        )

        // Preferences persist across coordinator relaunch
        let relaunchedGateway = FakeBrightnessHotkeyGateway()
        let relaunchedCoordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0,
            writeScheduler: ImmediateBrightnessWriteScheduler(),
            hotkeyGateway: relaunchedGateway,
            hotkeyPreferencesStore: store
        )
        XCTAssertEqual(
            relaunchedCoordinator.hotkeyPreferences,
            HotkeyPreferences(
                targetMode: .allEnabledDisplays,
                isMediaKeysEnabled: false,
                isLiteralF1F2Enabled: true
            )
        )
        XCTAssertEqual(relaunchedGateway.appliedPreferencesHistory.last, relaunchedCoordinator.hotkeyPreferences)

        // Termination stops the gateway cleanly
        relaunchedCoordinator.handleAppWillTerminate()
        XCTAssertEqual(relaunchedGateway.stopCount, 1)
    }

    func testUserDefaultsHotkeyPreferencesStoreRoundtripsPreferences() {
        let suiteName = "OpenBetterDisplayTests.HotkeyPrefs.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsHotkeyPreferencesStore(userDefaults: userDefaults)
        XCTAssertNil(store.loadPreferences())

        let expected = HotkeyPreferences(
            targetMode: .mainDisplay,
            isMediaKeysEnabled: false,
            isLiteralF1F2Enabled: true
        )
        store.savePreferences(expected)
        XCTAssertEqual(store.loadPreferences(), expected)
    }

    func testHotkeysAccordionAndLiveCheckerRefreshWithoutStartupAccessibilityPrompt() {
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(
                    displayID: 30,
                    name: "DELL U2725QE",
                    isBuiltIn: false,
                    isMain: true,
                    bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440)
                )
            ]
        )
        let gateway = FakeBrightnessHotkeyGateway(
            checkerStatus: KeyboardCheckerStatus(
                functionKeyMode: .standardFunctionKeys,
                isAccessibilityTrusted: false,
                isMediaKeyCaptureActive: false,
                isLiteralF1F2Active: false
            )
        )
        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0,
            writeScheduler: ImmediateBrightnessWriteScheduler(),
            hotkeyGateway: gateway,
            hotkeyPreferencesStore: InMemoryHotkeyPreferencesStore()
        )

        // Never auto-prompt Accessibility on startup
        XCTAssertEqual(gateway.accessibilityPermissionRequestCount, 0)
        XCTAssertEqual(
            coordinator.keyboardCheckerStatus,
            KeyboardCheckerStatus(
                functionKeyMode: .standardFunctionKeys,
                isAccessibilityTrusted: false,
                isMediaKeyCaptureActive: false,
                isLiteralF1F2Active: false
            )
        )

        // Single-open accordion across display card sections and footer .hotkeys
        coordinator.toggleExpandedSection(.displayMode(30))
        XCTAssertEqual(coordinator.expandedSection, .displayMode(30))

        // Gateway status changed externally before expanding .hotkeys -> expanding .hotkeys refreshes status
        gateway.checkerStatus = KeyboardCheckerStatus(
            functionKeyMode: .mediaKeys,
            isAccessibilityTrusted: false,
            isMediaKeyCaptureActive: false,
            isLiteralF1F2Active: false
        )
        coordinator.toggleExpandedSection(.hotkeys)
        XCTAssertEqual(coordinator.expandedSection, .hotkeys)
        XCTAssertEqual(coordinator.keyboardCheckerStatus.functionKeyMode, .mediaKeys)

        // Live distributed notification / focus change updates checker status immediately
        gateway.simulateCheckerStatusChange(
            KeyboardCheckerStatus(
                functionKeyMode: .standardFunctionKeys,
                isAccessibilityTrusted: true,
                isMediaKeyCaptureActive: true,
                isLiteralF1F2Active: false
            )
        )
        XCTAssertEqual(coordinator.keyboardCheckerStatus.functionKeyMode, .standardFunctionKeys)
        XCTAssertTrue(coordinator.keyboardCheckerStatus.isAccessibilityTrusted)
        XCTAssertTrue(coordinator.keyboardCheckerStatus.isMediaKeyCaptureActive)

        // Explicit buttons forward to gateway and refresh status
        coordinator.requestAccessibilityPermission()
        XCTAssertEqual(gateway.accessibilityPermissionRequestCount, 1)
        coordinator.openKeyboardSettings()
        XCTAssertEqual(gateway.openKeyboardSettingsCount, 1)

        // Expanding a display section collapses .hotkeys, and popover close collapses .hotkeys
        coordinator.toggleExpandedSection(.mainDisplay(30))
        XCTAssertEqual(coordinator.expandedSection, .mainDisplay(30))
        coordinator.toggleExpandedSection(.hotkeys)
        XCTAssertEqual(coordinator.expandedSection, .hotkeys)
        coordinator.handlePopoverDidClose()
        XCTAssertNil(coordinator.expandedSection)
    }

    func testRapidHotkeyRepeatsRespectDDCThrottlingWhileUpdatingUIAndHUDImmediately() {
        final class LocalScheduler: BrightnessWriteScheduling {
            final class Token: BrightnessWriteCancellable {
                let fireTime: TimeInterval
                let action: @MainActor () -> Void
                var isCancelled = false

                init(fireTime: TimeInterval, action: @escaping @MainActor () -> Void) {
                    self.fireTime = fireTime
                    self.action = action
                }

                func cancel() { isCancelled = true }
            }

            var currentTime: TimeInterval = 0
            var tokens: [Token] = []

            func now() -> TimeInterval { currentTime }

            func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> BrightnessWriteCancellable {
                let token = Token(fireTime: currentTime + max(0, delay), action: action)
                tokens.append(token)
                return token
            }

            func performWrite(
                _ work: @escaping @Sendable () -> BrightnessBackendUsed,
                completion: @escaping @MainActor (BrightnessBackendUsed) -> Void
            ) {
                completion(work())
            }

            func advance(by interval: TimeInterval) {
                currentTime += interval
                while let next = tokens.filter({ !$0.isCancelled && $0.fireTime <= currentTime + 1e-9 }).first {
                    tokens.removeAll { $0 === next }
                    next.action()
                }
            }
        }

        let scheduler = LocalScheduler()
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(
                    displayID: 30,
                    name: "DELL U2725QE",
                    isBuiltIn: false,
                    isMain: true,
                    bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440)
                )
            ],
            brightnessReadings: [
                30: BrightnessReading(level: 0.50, backend: .hardwareDDC)
            ]
        )
        let gateway = FakeBrightnessHotkeyGateway()
        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0.06,
            writeScheduler: scheduler,
            hotkeyGateway: gateway,
            hotkeyPreferencesStore: InMemoryHotkeyPreferencesStore()
        )

        // Initial press fires leading DDC write immediately
        XCTAssertTrue(gateway.simulateKeyEvent(BrightnessKeyEvent(direction: .increase, source: .mediaBrightness)))
        XCTAssertEqual(driver.setBrightnessHistory.map(\.level), [0.5625])
        XCTAssertEqual(coordinator.lastBrightnessHUDUpdates.first?.brightnessPercentage, 56)

        // Rapid hold-repeats coalesce inside 60ms DDC throttle window while updating UI & HUD immediately
        scheduler.advance(by: 0.01)
        XCTAssertTrue(
            gateway.simulateKeyEvent(BrightnessKeyEvent(direction: .increase, source: .mediaBrightness, isRepeat: true))
        )
        scheduler.advance(by: 0.01)
        XCTAssertTrue(
            gateway.simulateKeyEvent(BrightnessKeyEvent(direction: .increase, source: .mediaBrightness, isRepeat: true))
        )
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)
        XCTAssertEqual(coordinator.displays.first?.brightness ?? -1, 0.6875, accuracy: 0.0001)
        XCTAssertEqual(coordinator.lastBrightnessHUDUpdates.first?.brightnessPercentage, 69)

        // Completing the throttle window flushes final value (0.6875)
        scheduler.advance(by: 0.05)
        XCTAssertEqual(driver.setBrightnessHistory.count, 2)
        XCTAssertEqual(driver.setBrightnessHistory.last?.level ?? -1, 0.6875, accuracy: 0.0001)
    }

    func testMediaBrightnessPayloadParserAndCoordinateConversionAndFnModeResolution() {
        // NX_KEYTYPE_BRIGHTNESS_UP (2), keyDown (0x0A), initial press (0), Option+Shift fine step
        let upFineData1 = (2 << 16) | 0x0A00
        let upFine = BrightnessKeyEventParser.parseMediaKeyData(
            data1: upFineData1,
            isFineModifierActive: true,
            pointerLocation: CGPoint(x: 100, y: 200)
        )
        XCTAssertEqual(upFine?.keyCode, 2)
        XCTAssertEqual(upFine?.isKeyDown, true)
        XCTAssertEqual(upFine?.isKeyUp, false)
        XCTAssertEqual(
            upFine?.event,
            BrightnessKeyEvent(
                direction: .increase,
                source: .mediaBrightness,
                isFine: true,
                isRepeat: false,
                pointerLocation: CGPoint(x: 100, y: 200)
            )
        )

        // NX_KEYTYPE_BRIGHTNESS_DOWN (3), keyDown (0x0A), repeat bit (0x0001)
        let downRepeatData1 = (3 << 16) | 0x0A01
        let downRepeat = BrightnessKeyEventParser.parseMediaKeyData(
            data1: downRepeatData1,
            isFineModifierActive: false,
            pointerLocation: nil
        )
        XCTAssertEqual(downRepeat?.keyCode, 3)
        XCTAssertEqual(downRepeat?.isKeyDown, true)
        XCTAssertEqual(
            downRepeat?.event,
            BrightnessKeyEvent(
                direction: .decrease,
                source: .mediaBrightness,
                isFine: false,
                isRepeat: true,
                pointerLocation: nil
            )
        )

        // Key-up (0x0B) is flagged as keyUp so matching consumed keyDown can suppress keyUp cleanly
        let upRelease = BrightnessKeyEventParser.parseMediaKeyData(
            data1: (2 << 16) | 0x0B00,
            isFineModifierActive: false,
            pointerLocation: nil
        )
        XCTAssertEqual(upRelease?.isKeyDown, false)
        XCTAssertEqual(upRelease?.isKeyUp, true)

        // Unrelated media keys (e.g. sound volume up = 0) are ignored
        XCTAssertNil(
            BrightnessKeyEventParser.parseMediaKeyData(
                data1: 0x0A00,
                isFineModifierActive: false,
                pointerLocation: nil
            )
        )

        // AppKit bottom-left mouseLocation -> CoreGraphics top-left global coordinate
        let cgPoint = BrightnessKeyEventParser.convertAppKitPointerToCoreGraphics(
            CGPoint(x: -500, y: 900),
            mainDisplayHeight: 1440
        )
        XCTAssertEqual(cgPoint, CGPoint(x: -500, y: 540))

        // HIDFKeyMode takes precedence; CFPreferences fnState serves as fallback
        XCTAssertEqual(BrightnessKeyEventParser.resolveFunctionKeyMode(hidFKeyMode: 0, cfPreferenceFnState: true), .mediaKeys)
        XCTAssertEqual(
            BrightnessKeyEventParser.resolveFunctionKeyMode(hidFKeyMode: 1, cfPreferenceFnState: false),
            .standardFunctionKeys
        )
        XCTAssertEqual(
            BrightnessKeyEventParser.resolveFunctionKeyMode(hidFKeyMode: nil, cfPreferenceFnState: true),
            .standardFunctionKeys
        )
        XCTAssertEqual(BrightnessKeyEventParser.resolveFunctionKeyMode(hidFKeyMode: nil, cfPreferenceFnState: false), .mediaKeys)
        XCTAssertEqual(BrightnessKeyEventParser.resolveFunctionKeyMode(hidFKeyMode: nil, cfPreferenceFnState: nil), .unknown)
    }
}
