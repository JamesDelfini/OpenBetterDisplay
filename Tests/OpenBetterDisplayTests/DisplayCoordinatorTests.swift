import XCTest

@testable import OpenBetterDisplayCore

@MainActor
final class DisplayCoordinatorTests: XCTestCase {
    func testDiscoversConnectedDisplaysWithHumanReadableNamesInConsistentOrder() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        XCTAssertEqual(
            coordinator.displays.map(\.name),
            ["Built-in Display", "DELL P2217H", "DELL U2725QE"]
        )
        XCTAssertEqual(
            coordinator.displays.map(\.displayID),
            [1, 20, 30]
        )
    }

    func testClassifiesBuiltInAndExternalDisplaysWithMatchingSystemIcons() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        XCTAssertEqual(coordinator.displays.map(\.isBuiltIn), [true, false, false])
        XCTAssertEqual(
            coordinator.displays.map(\.symbolName),
            ["laptopcomputer", "display", "display"]
        )
    }

    func testIdentifiesCurrentMainDisplayForMBadge() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        XCTAssertEqual(coordinator.displays.map(\.isMain), [false, false, true])
        XCTAssertEqual(coordinator.displays.first(where: \.isMain)?.name, "DELL U2725QE")
    }

    func testNormalizesRawSystemDisplayNamesToHumanReadableLabels() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Retina Display", isBuiltIn: true, isMain: true),
            RawDisplayInfo(displayID: 20, name: "  DELL P2217H  ", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "", isBuiltIn: false, isMain: false, vendorID: 0x10AC, modelID: 0xD0B3)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        XCTAssertEqual(
            coordinator.displays.map(\.name),
            ["Built-in Display", "DELL P2217H", "External Display (10AC:D0B3)"]
        )
    }

    func testUpdatesDisplayListWhenMonitorsArePluggedUnpluggedOrReconfigured() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.map(\.name), ["Built-in Display"])
        XCTAssertEqual(coordinator.displays.map(\.isMain), [true])

        // Plug in two external monitors and promote DELL U2725QE to Main Display
        driver.onlineDisplays = [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ]
        coordinator.handleDisplayReconfiguration()

        XCTAssertEqual(
            coordinator.displays.map(\.name),
            ["Built-in Display", "DELL P2217H", "DELL U2725QE"]
        )
        XCTAssertEqual(coordinator.displays.map(\.isMain), [false, false, true])

        // Unplug DELL P2217H
        driver.onlineDisplays = [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ]
        coordinator.handleDisplayReconfiguration()

        XCTAssertEqual(
            coordinator.displays.map(\.name),
            ["Built-in Display", "DELL U2725QE"]
        )
    }

    func testBuiltInDisplayReadsInitialSystemBrightnessAndRoutesAdjustmentsToNativeBacklight() {
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: true)
            ],
            brightnessReadings: [
                1: BrightnessReading(level: 0.65, backend: .nativeAppleBacklight)
            ]
        )

        let coordinator = DisplayCoordinator(driver: driver, brightnessStore: InMemoryBrightnessStore())

        XCTAssertEqual(coordinator.displays.first?.brightness, 0.65)
        XCTAssertEqual(coordinator.displays.first?.brightnessPercentage, 65)
        XCTAssertEqual(coordinator.displays.first?.brightnessBackend, .nativeAppleBacklight)

        coordinator.setBrightness(1, level: 0.42)

        XCTAssertEqual(coordinator.displays.first?.brightness, 0.42)
        XCTAssertEqual(coordinator.displays.first?.brightnessPercentage, 42)
        XCTAssertEqual(coordinator.displays.first?.brightnessBackend, .nativeAppleBacklight)
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)
        XCTAssertEqual(driver.setBrightnessHistory.first?.displayID, 1)
        XCTAssertEqual(driver.setBrightnessHistory.first?.level, 0.42)

        // External system brightness key changes sync cleanly on routine refresh
        driver.brightnessReadings[1] = BrightnessReading(level: 0.80, backend: .nativeAppleBacklight)
        coordinator.refreshDisplays()
        XCTAssertEqual(coordinator.displays.first?.brightness, 0.80)
        XCTAssertEqual(coordinator.displays.first?.brightnessPercentage, 80)
    }

    func testBuiltInDisplayReadsLiveSystemBrightnessOnLaunchWithoutOverwritingMacOSWithStalePersistedValue() {
        let store = InMemoryBrightnessStore(initialValues: [
            "builtin": 0.70,
            "hardware:10AC:D0B3:12345678": 0.45
        ])
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
                RawDisplayInfo(
                    displayID: 20,
                    name: "DELL P2217H",
                    isBuiltIn: false,
                    isMain: true,
                    vendorID: 0x10AC,
                    modelID: 0xD0B3,
                    serialNumber: 0x12345678
                )
            ],
            brightnessReadings: [
                1: BrightnessReading(level: 0.35, backend: .nativeAppleBacklight),
                20: BrightnessReading(level: 1.0, backend: .hardwareDDC)
            ]
        )

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: store,
            ddcThrottleInterval: 0,
            writeScheduler: ImmediateBrightnessWriteScheduler()
        )

        // Built-in display reads live system brightness (0.35) instead of overwriting macOS with stale 0.70
        let builtIn = coordinator.displays.first(where: { $0.displayID == 1 })
        XCTAssertEqual(builtIn?.brightness, 0.35)
        XCTAssertEqual(builtIn?.brightnessPercentage, 35)
        XCTAssertEqual(store.brightness(forKey: "builtin"), 0.35)
        XCTAssertFalse(driver.setBrightnessHistory.contains(where: { $0.displayID == 1 }))

        // External display still restores its persisted brightness (0.45) on launch
        let external = coordinator.displays.first(where: { $0.displayID == 20 })
        XCTAssertEqual(external?.brightness, 0.45)
        XCTAssertEqual(external?.brightnessPercentage, 45)
        XCTAssertEqual(driver.setBrightnessHistory.filter { $0.displayID == 20 }.map(\.level), [0.45])
    }

    func testBuiltInDisplaySyncsExternalMacOSBrightnessKeyChangesWithoutPollingExternalMonitors() {
        let store = InMemoryBrightnessStore()
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
                RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: true)
            ],
            brightnessReadings: [
                1: BrightnessReading(level: 0.50, backend: .nativeAppleBacklight),
                20: BrightnessReading(level: 0.80, backend: .hardwareDDC)
            ]
        )

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: store,
            ddcThrottleInterval: 0,
            writeScheduler: ImmediateBrightnessWriteScheduler()
        )
        coordinator.setBrightness(1, level: 0.42)
        XCTAssertEqual(store.brightness(forKey: "builtin"), 0.42)

        // User presses MacBook brightness keys outside OpenBetterDisplay -> macOS moves backlight to 0.78
        driver.brightnessReadings[1] = BrightnessReading(level: 0.78, backend: .nativeAppleBacklight)
        driver.getBrightnessHistory.removeAll()
        driver.setBrightnessHistory.removeAll()

        coordinator.syncBuiltInBrightness()

        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 1 })?.brightness, 0.78)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 1 })?.brightnessPercentage, 78)
        XCTAssertEqual(store.brightness(forKey: "builtin"), 0.78)
        // Must only query built-in display (no I2C DDC polling of external display 20) and never overwrite macOS
        XCTAssertEqual(driver.getBrightnessHistory, [1])
        XCTAssertTrue(driver.setBrightnessHistory.isEmpty)

        // Another brightness key press followed by popover-open refreshDisplays() also updates state and store
        driver.brightnessReadings[1] = BrightnessReading(level: 0.25, backend: .nativeAppleBacklight)
        coordinator.refreshDisplays()
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 1 })?.brightness, 0.25)
        XCTAssertEqual(store.brightness(forKey: "builtin"), 0.25)
        XCTAssertTrue(driver.setBrightnessHistory.isEmpty)
    }

    func testExternalDDCCapableMonitorRoutesBrightnessToHardwareDDCAndClampsBounds() {
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: true)
            ],
            brightnessReadings: [
                20: BrightnessReading(level: 0.80, backend: .hardwareDDC)
            ]
        )

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0,
            writeScheduler: ImmediateBrightnessWriteScheduler()
        )

        XCTAssertEqual(coordinator.displays.first?.brightness, 0.80)
        XCTAssertEqual(coordinator.displays.first?.brightnessPercentage, 80)
        XCTAssertEqual(coordinator.displays.first?.brightnessBackend, .hardwareDDC)

        coordinator.setBrightness(20, level: 0.55)
        XCTAssertEqual(coordinator.displays.first?.brightness, 0.55)
        XCTAssertEqual(coordinator.displays.first?.brightnessPercentage, 55)
        XCTAssertEqual(coordinator.displays.first?.brightnessBackend, .hardwareDDC)
        XCTAssertEqual(driver.setBrightnessHistory.last?.displayID, 20)
        XCTAssertEqual(driver.setBrightnessHistory.last?.level, 0.55)

        coordinator.setBrightness(20, level: 1.4)
        XCTAssertEqual(coordinator.displays.first?.brightness, 1.0)
        XCTAssertEqual(coordinator.displays.first?.brightnessPercentage, 100)
        XCTAssertEqual(driver.setBrightnessHistory.last?.level, 1.0)

        coordinator.setBrightness(20, level: -0.25)
        XCTAssertEqual(coordinator.displays.first?.brightness, 0.0)
        XCTAssertEqual(coordinator.displays.first?.brightnessPercentage, 0)
        XCTAssertEqual(driver.setBrightnessHistory.last?.level, 0.0)
    }

    func testHardwareDDCBrightnessDragUpdatesUIStateImmediatelyWhileThrottlingDriverWrites() {
        let scheduler = ManualBrightnessWriteScheduler()
        let store = InMemoryBrightnessStore()
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: true)
            ],
            brightnessReadings: [
                20: BrightnessReading(level: 1.0, backend: .hardwareDDC)
            ]
        )

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: store,
            ddcThrottleInterval: 0.06,
            writeScheduler: scheduler
        )

        // Leading edge fires immediately
        coordinator.setBrightness(20, level: 0.90)
        XCTAssertEqual(coordinator.displays.first?.brightness, 0.90)
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)
        XCTAssertEqual(driver.setBrightnessHistory.last?.level, 0.90)

        // Rapid slider scrub within throttle window updates UI immediately without flooding DDC bus
        scheduler.advance(by: 0.01)
        coordinator.setBrightness(20, level: 0.80)
        scheduler.advance(by: 0.01)
        coordinator.setBrightness(20, level: 0.70)
        scheduler.advance(by: 0.01)
        coordinator.setBrightness(20, level: 0.55)

        XCTAssertEqual(coordinator.displays.first?.brightness, 0.55)
        XCTAssertEqual(coordinator.displays.first?.brightnessPercentage, 55)
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)

        // A routine refresh while trailing write is pending preserves the user's target slider position
        coordinator.refreshDisplays()
        XCTAssertEqual(coordinator.displays.first?.brightness, 0.55)

        // Completing the throttle window flushes the latest coalesced value once
        scheduler.advance(by: 0.03)
        XCTAssertEqual(driver.setBrightnessHistory.count, 2)
        XCTAssertEqual(driver.setBrightnessHistory.last?.displayID, 20)
        XCTAssertEqual(driver.setBrightnessHistory.last?.level, 0.55)

        // Further movement after throttle window fires smoothly again
        scheduler.advance(by: 0.07)
        coordinator.setBrightness(20, level: 0.35)
        XCTAssertEqual(driver.setBrightnessHistory.count, 3)
        XCTAssertEqual(driver.setBrightnessHistory.last?.level, 0.35)
    }

    func testNativeBacklightAndSoftwareGammaWritesBypassDDCThrottling() {
        let scheduler = ManualBrightnessWriteScheduler()
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
                RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
            ],
            unsupportedDDCDisplayIDs: [30]
        )

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0.06,
            writeScheduler: scheduler
        )

        coordinator.setBrightness(1, level: 0.80)
        coordinator.setBrightness(1, level: 0.60)
        coordinator.setBrightness(30, level: 0.50)
        coordinator.setBrightness(30, level: 0.30)

        XCTAssertEqual(driver.setBrightnessHistory.count, 4)
        XCTAssertEqual(driver.setBrightnessHistory.map(\.level), [0.80, 0.60, 0.50, 0.30])
    }

    func testDDCWriteFallbackToSoftwareGammaUpdatesBackendAndAppliesSubsequentChangesImmediately() {
        let scheduler = ManualBrightnessWriteScheduler()
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: true)
            ],
            brightnessReadings: [
                20: BrightnessReading(level: 0.90, backend: .hardwareDDC)
            ]
        )

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0.06,
            writeScheduler: scheduler
        )

        // DDC fails at write time and driver falls back to software gamma
        driver.unsupportedDDCDisplayIDs.insert(20)
        coordinator.setBrightness(20, level: 0.70)

        XCTAssertEqual(coordinator.displays.first?.brightnessBackend, .softwareGamma)
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)

        // Subsequent rapid writes now bypass DDC throttling
        coordinator.setBrightness(20, level: 0.50)
        coordinator.setBrightness(20, level: 0.40)
        XCTAssertEqual(driver.setBrightnessHistory.count, 3)
        XCTAssertEqual(driver.setBrightnessHistory.map(\.level), [0.70, 0.50, 0.40])
    }

    func testPendingDDCWritesAreCancelledOnTerminationAndDisplayUnplug() {
        let scheduler = ManualBrightnessWriteScheduler()
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: true),
                RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false)
            ]
        )

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0.06,
            writeScheduler: scheduler
        )

        coordinator.setBrightness(20, level: 0.80)
        scheduler.advance(by: 0.01)
        coordinator.setBrightness(20, level: 0.40)
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)

        // Unplugging monitor 20 cancels its pending trailing DDC write
        driver.onlineDisplays = [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: true)
        ]
        coordinator.handleDisplayReconfiguration()
        scheduler.advance(by: 0.10)
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)

        // Reconnect monitor 20 (restores persisted 0.40), then queue a pending write and terminate app
        driver.onlineDisplays = [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: true),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false)
        ]
        coordinator.handleDisplayReconfiguration()
        let countAfterReconnect = driver.setBrightnessHistory.count

        coordinator.setBrightness(20, level: 0.75)
        scheduler.advance(by: 0.01)
        coordinator.setBrightness(20, level: 0.25)
        XCTAssertEqual(driver.setBrightnessHistory.count, countAfterReconnect + 1)

        coordinator.handleAppWillTerminate()
        scheduler.advance(by: 0.10)
        XCTAssertTrue(driver.didResetSoftwareGamma)
        XCTAssertEqual(driver.setBrightnessHistory.count, countAfterReconnect + 1)
    }

    func testCoalescesUpdatesWhileAsyncDDCWriteIsInFlightWithoutOverlappingBusWrites() {
        let scheduler = ManualBrightnessWriteScheduler(deferWriteCompletions: true)
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: true)
            ],
            brightnessReadings: [
                20: BrightnessReading(level: 1.0, backend: .hardwareDDC)
            ]
        )

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            ddcThrottleInterval: 0.06,
            writeScheduler: scheduler
        )

        // Start leading write (in-flight asynchronously)
        coordinator.setBrightness(20, level: 0.85)
        XCTAssertEqual(scheduler.pendingWriteCount, 1)
        XCTAssertEqual(driver.setBrightnessHistory.count, 0)

        // While first write is still in-flight, user scrubs further and a refresh occurs
        scheduler.advance(by: 0.07)
        coordinator.setBrightness(20, level: 0.65)
        coordinator.setBrightness(20, level: 0.40)
        coordinator.refreshDisplays()

        // No overlapping second write launched yet; UI preserves latest target
        XCTAssertEqual(scheduler.pendingWriteCount, 1)
        XCTAssertEqual(coordinator.displays.first?.brightness, 0.40)

        // First write completes -> immediately dispatches latest coalesced value (0.40) since throttle window elapsed
        scheduler.completeNextWrite()
        XCTAssertEqual(driver.setBrightnessHistory.map(\.level), [0.85])
        XCTAssertEqual(scheduler.pendingWriteCount, 1)

        // Second write completes
        scheduler.completeNextWrite()
        XCTAssertEqual(driver.setBrightnessHistory.map(\.level), [0.85, 0.40])
        XCTAssertEqual(scheduler.pendingWriteCount, 0)
    }

    func testExternalMonitorWithoutDDCSupportFallsBackToSoftwareGammaAndResetsOnTermination() {
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
            ],
            unsupportedDDCDisplayIDs: [30]
        )

        let coordinator = DisplayCoordinator(driver: driver, brightnessStore: InMemoryBrightnessStore())

        coordinator.setBrightness(30, level: 0.30)

        XCTAssertEqual(coordinator.displays.first?.brightness, 0.30)
        XCTAssertEqual(coordinator.displays.first?.brightnessPercentage, 30)
        XCTAssertEqual(coordinator.displays.first?.brightnessBackend, .softwareGamma)
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)
        XCTAssertEqual(driver.setBrightnessHistory.first?.displayID, 30)
        XCTAssertEqual(driver.setBrightnessHistory.first?.level, 0.30)
        XCTAssertFalse(driver.didResetSoftwareGamma)

        coordinator.handleAppWillTerminate()

        XCTAssertTrue(driver.didResetSoftwareGamma)
    }

    func testTurningDisplayOffCancelsPendingDDCWritesAndReEnablingRestoresPersistedBrightness() {
        let scheduler = ManualBrightnessWriteScheduler()
        let store = InMemoryBrightnessStore()
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: true),
                RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false)
            ]
        )

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: store,
            ddcThrottleInterval: 0.06,
            writeScheduler: scheduler
        )

        coordinator.setBrightness(20, level: 0.70)
        scheduler.advance(by: 0.01)
        coordinator.setBrightness(20, level: 0.35)
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)

        // Turning off display 20 cancels pending trailing DDC write and ignores further brightness changes
        coordinator.setDisplayEnabled(20, enabled: false)
        scheduler.advance(by: 0.10)
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)

        coordinator.setBrightness(20, level: 0.90)
        XCTAssertEqual(driver.setBrightnessHistory.count, 1)

        // Re-enabling display 20 restores its last persisted brightness (0.35) even if hardware reported 100%
        driver.brightnessReadings[20] = BrightnessReading(level: 1.0, backend: .hardwareDDC)
        coordinator.setDisplayEnabled(20, enabled: true)

        let reEnabled = coordinator.displays.first(where: { $0.displayID == 20 })
        XCTAssertEqual(reEnabled?.isEnabled, true)
        XCTAssertEqual(reEnabled?.brightness, 0.35)
        XCTAssertEqual(reEnabled?.brightnessPercentage, 35)
        XCTAssertEqual(driver.brightnessReadings[20]?.level, 0.35)
    }

    func testExposesSafeAtLeast720pModesAndHidesUnsafeStretchedAndSub720pModes() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 100,
                width: 3840,
                height: 2160,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 102,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 120.0,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 101,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 103,
                width: 1920,
                height: 1080,
                pixelWidth: 1920,
                pixelHeight: 1080,
                refreshRate: 60.0,
                bitsPerSample: 8
            ),
            // Sub-720p mode must be excluded even if marked usable
            RawDisplayMode(
                modeID: 201,
                width: 960,
                height: 540,
                pixelWidth: 1920,
                pixelHeight: 1080,
                refreshRate: 60.0
            ),
            RawDisplayMode(
                modeID: 202,
                width: 800,
                height: 600,
                pixelWidth: 800,
                pixelHeight: 600,
                refreshRate: 60.0
            ),
            // Stretched mode must be excluded even if >= 720p
            RawDisplayMode(
                modeID: 203,
                width: 1600,
                height: 1200,
                pixelWidth: 1600,
                pixelHeight: 1200,
                refreshRate: 60.0,
                isStretched: true
            ),
            // Unsafe mode must be excluded
            RawDisplayMode(
                modeID: 204,
                width: 1920,
                height: 1200,
                pixelWidth: 3840,
                pixelHeight: 2400,
                refreshRate: 60.0,
                isUsableForDesktopGUI: false
            )
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                currentModeID: 102,
                modes: modes
            )
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        guard let display = coordinator.displays.first else {
            XCTFail("Expected display")
            return
        }

        XCTAssertEqual(display.availableModes.map(\.modeID), [100, 102, 101, 103])
        XCTAssertEqual(display.resolutionLabel, "2560x1440")
        XCTAssertEqual(display.currentModeID, 102)
        XCTAssertEqual(display.defaultMode?.modeID, 101)
        XCTAssertEqual(display.nativeMode?.modeID, 100)
    }

    func testResolvesNativeModeStrictlyAsOneToOnePhysicalPixelGridEvenWhenHiDPIAlsoHasNativeFlag() {
        let builtInModes: [RawDisplayMode] = [
            // macOS sets kDisplayModeNativeFlag on both 1x 3024x1964 and 2x HiDPI 1512x982
            RawDisplayMode(
                modeID: 54,
                width: 1512,
                height: 982,
                pixelWidth: 3024,
                pixelHeight: 1964,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 10,
                width: 3024,
                height: 1964,
                pixelWidth: 3024,
                pixelHeight: 1964,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 11,
                width: 3024,
                height: 1964,
                pixelWidth: 3024,
                pixelHeight: 1964,
                refreshRate: 60.0,
                isNative: true,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 55,
                width: 1147,
                height: 745,
                pixelWidth: 2294,
                pixelHeight: 1490,
                refreshRate: 120.0,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 56,
                width: 1024,
                height: 665,
                pixelWidth: 2048,
                pixelHeight: 1330,
                refreshRate: 120.0,
                bitsPerSample: 10
            )
        ]

        let standard1080pModes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 32,
                width: 1920,
                height: 1080,
                pixelWidth: 1920,
                pixelHeight: 1080,
                refreshRate: 60.0,
                isNative: true,
                bitsPerSample: 8,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 31,
                width: 960,
                height: 540,
                pixelWidth: 1920,
                pixelHeight: 1080,
                refreshRate: 60.0,
                isNative: true,
                bitsPerSample: 8
            )
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false, currentModeID: 54, modes: builtInModes),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: true, currentModeID: 32, modes: standard1080pModes)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        let builtIn = coordinator.displays[0]
        XCTAssertEqual(builtIn.defaultMode?.modeID, 54)
        XCTAssertEqual(builtIn.nativeMode?.modeID, 10)
        XCTAssertEqual(builtIn.nativeMode?.isHiDPI, false)
        XCTAssertEqual(builtIn.availableModes.map(\.modeID), [10, 11, 54, 55])

        let dell = coordinator.displays[1]
        XCTAssertEqual(dell.defaultMode?.modeID, 32)
        XCTAssertEqual(dell.nativeMode?.modeID, 32)
        XCTAssertEqual(dell.availableModes.map(\.modeID), [32])
    }

    func testFormatsDisplayModeMetadataBadgesForHiDPIAspectRatioRefreshRateAndColorDepth() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 1,
                width: 2400,
                height: 1350,
                pixelWidth: 4800,
                pixelHeight: 2700,
                refreshRate: 120.0,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 2,
                width: 1512,
                height: 982,
                pixelWidth: 3024,
                pixelHeight: 1964,
                refreshRate: 59.94,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 3,
                width: 1920,
                height: 1200,
                pixelWidth: 1920,
                pixelHeight: 1200,
                refreshRate: 60.0,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 4,
                width: 1280,
                height: 1024,
                pixelWidth: 1280,
                pixelHeight: 1024,
                refreshRate: 75.0,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 5,
                width: 1024,
                height: 768,
                pixelWidth: 1024,
                pixelHeight: 768,
                refreshRate: 0.0,
                bitsPerSample: 8
            )
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true, currentModeID: 1, modes: modes)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        let byID = Dictionary(uniqueKeysWithValues: (coordinator.displays.first?.availableModes ?? []).map { ($0.modeID, $0) })

        XCTAssertEqual(byID[1]?.resolutionLabel, "2400x1350")
        XCTAssertEqual(byID[1]?.isHiDPI, true)
        XCTAssertEqual(byID[1]?.aspectRatioLabel, "16:9")
        XCTAssertEqual(byID[1]?.refreshRateLabel, "120Hz")
        XCTAssertEqual(byID[1]?.colorDepthLabel, "10bit")

        XCTAssertEqual(byID[2]?.resolutionLabel, "1512x982")
        XCTAssertEqual(byID[2]?.isHiDPI, true)
        XCTAssertEqual(byID[2]?.isDefault, true)
        XCTAssertEqual(byID[2]?.isNative, false)
        XCTAssertEqual(byID[2]?.aspectRatioLabel, "15.4:10")
        XCTAssertEqual(byID[2]?.refreshRateLabel, "59.94Hz")
        XCTAssertEqual(byID[2]?.colorDepthLabel, "10bit")

        XCTAssertEqual(byID[3]?.isHiDPI, false)
        XCTAssertEqual(byID[3]?.aspectRatioLabel, "16:10")
        XCTAssertEqual(byID[3]?.refreshRateLabel, "60Hz")
        XCTAssertEqual(byID[3]?.colorDepthLabel, "8bit")

        XCTAssertEqual(byID[4]?.aspectRatioLabel, "5:4")
        XCTAssertEqual(byID[4]?.refreshRateLabel, "75Hz")

        XCTAssertEqual(byID[5]?.aspectRatioLabel, "4:3")
        XCTAssertNil(byID[5]?.refreshRateLabel)
    }

    func testSelectingDisplayModeSwitchesImmediatelyAndUpdatesCurrentModeAndSummary() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 100,
                width: 3840,
                height: 2160,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 101,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 102,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 120.0,
                bitsPerSample: 10
            )
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true, currentModeID: 101, modes: modes)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "1920x1080")
        XCTAssertTrue(driver.setModeHistory.isEmpty)

        coordinator.selectDisplayMode(30, modeID: 102)
        XCTAssertEqual(driver.setModeHistory.count, 1)
        XCTAssertEqual(driver.setModeHistory.first?.displayID, 30)
        XCTAssertEqual(driver.setModeHistory.first?.modeID, 102)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 102)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "2560x1440")

        // Clicking already-active mode does not invoke driver again
        coordinator.selectDisplayMode(30, modeID: 102)
        XCTAssertEqual(driver.setModeHistory.count, 1)

        // Switching to Native Mode works immediately
        coordinator.selectDisplayMode(30, modeID: 100)
        XCTAssertEqual(driver.setModeHistory.count, 2)
        XCTAssertEqual(driver.setModeHistory.last?.modeID, 100)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 100)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "3840x2160")
    }

    func testFilteredOutActiveModePreservesRealResolutionAndAllowsSwitchingToSafeMode() {
        let modes: [RawDisplayMode] = [
            // Active sub-720p mode hidden from browser list
            RawDisplayMode(modeID: 99, width: 800, height: 600, pixelWidth: 800, pixelHeight: 600, refreshRate: 60.0),
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true, currentModeID: 99, modes: modes)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.first?.availableModes.map(\.modeID), [102, 101])
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 99)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "800x600")

        coordinator.selectDisplayMode(30, modeID: 101)
        XCTAssertEqual(driver.setModeHistory.count, 1)
        XCTAssertEqual(driver.setModeHistory.first?.modeID, 101)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 101)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "1920x1080")
    }

    func testFailedDisplayModeSwitchPreservesPreviousCurrentModeAndSummary() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true, currentModeID: 101, modes: modes)
        ])
        driver.setDisplayModeError = DisplayDriverError.configurationFailed(-1)

        let coordinator = DisplayCoordinator(driver: driver)
        coordinator.selectDisplayMode(30, modeID: 102)

        XCTAssertEqual(driver.setModeHistory.count, 1)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 101)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "1920x1080")
    }

    func testDisplayModeSelectionIsIgnoredForDisabledDisplay() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: false,
                isActive: false,
                currentModeID: 101,
                modes: modes
            )
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.first?.isEnabled, false)

        coordinator.selectDisplayMode(30, modeID: 102)
        XCTAssertTrue(driver.setModeHistory.isEmpty)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 101)
    }

    func testTogglingActiveNonMainDisplayOffDisconnectsAtOSLevelAndRetainsDisplayInOffState() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, true, true])
        XCTAssertFalse(coordinator.hasDisconnectedDisplays)

        coordinator.setDisplayEnabled(20, enabled: false)

        XCTAssertEqual(driver.enabledHistory.count, 1)
        XCTAssertEqual(driver.enabledHistory.first?.displayID, 20)
        XCTAssertEqual(driver.enabledHistory.first?.enabled, false)
        XCTAssertFalse(driver.fetchOnlineDisplays().contains(where: { $0.displayID == 20 }))

        // Simulate macOS display reconfiguration notification firing after disconnect
        coordinator.handleDisplayReconfiguration()

        XCTAssertEqual(coordinator.displays.map(\.displayID), [1, 20, 30])
        XCTAssertEqual(coordinator.displays.map(\.name), ["Built-in Display", "DELL P2217H", "DELL U2725QE"])
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, false, true])
        XCTAssertTrue(coordinator.hasDisconnectedDisplays)
    }

    func testTogglingDisconnectedDisplayOnReEnablesAtOSLevelAndRestoresEnabledState() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        coordinator.toggleDisplayEnabled(20)
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, false, true])
        XCTAssertTrue(coordinator.hasDisconnectedDisplays)

        coordinator.toggleDisplayEnabled(20)

        XCTAssertEqual(driver.enabledHistory.count, 2)
        XCTAssertEqual(driver.enabledHistory.last?.displayID, 20)
        XCTAssertEqual(driver.enabledHistory.last?.enabled, true)
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, true, true])
        XCTAssertFalse(coordinator.hasDisconnectedDisplays)
    }

    func testReconnectAllDisplaysReEnablesEveryTurnedOffDisplay() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        coordinator.setDisplayEnabled(1, enabled: false)
        coordinator.setDisplayEnabled(20, enabled: false)

        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [false, false, true])
        XCTAssertTrue(coordinator.hasDisconnectedDisplays)

        coordinator.reconnectAllDisplays()

        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, true, true])
        XCTAssertFalse(coordinator.hasDisconnectedDisplays)
        XCTAssertEqual(driver.enabledHistory.map(\.displayID), [1, 20, 1, 20])
        XCTAssertEqual(driver.enabledHistory.map(\.enabled), [false, false, true, true])
    }

    func testMainDisplayCannotBeToggledOffUntilMainStatusIsTransferred() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        XCTAssertEqual(coordinator.displays.map(\.canToggleOff), [true, true, false])
        XCTAssertFalse(coordinator.canToggleOff(30))

        // Attempting to turn off the Main Display is a safe no-op
        coordinator.setDisplayEnabled(30, enabled: false)
        XCTAssertTrue(driver.enabledHistory.isEmpty)
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, true, true])

        // Transfer Main Display status ("M") to DELL P2217H (display 20)
        coordinator.setMainDisplay(20)

        XCTAssertEqual(driver.mainDisplayHistory, [20])
        XCTAssertEqual(coordinator.displays.map(\.isMain), [false, true, false])
        XCTAssertEqual(coordinator.displays.map(\.canToggleOff), [true, false, true])
        XCTAssertFalse(coordinator.canToggleOff(20))
        XCTAssertTrue(coordinator.canToggleOff(30))

        // Now the former Main Display (30) can be turned off
        coordinator.setDisplayEnabled(30, enabled: false)
        XCTAssertEqual(driver.enabledHistory.count, 1)
        XCTAssertEqual(driver.enabledHistory.first?.displayID, 30)
        XCTAssertEqual(driver.enabledHistory.first?.enabled, false)
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, true, false])
    }

    func testLastRemainingActiveDisplayCannotBeToggledOff() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: false)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.map(\.canToggleOff), [true, true, true])

        coordinator.setDisplayEnabled(1, enabled: false)
        coordinator.setDisplayEnabled(20, enabled: false)

        // Only display 30 remains active — must be locked from turning off even if isMain == false
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [false, false, true])
        XCTAssertEqual(coordinator.displays.map(\.canToggleOff), [false, false, false])
        XCTAssertFalse(coordinator.canToggleOff(30))

        coordinator.setDisplayEnabled(30, enabled: false)
        XCTAssertEqual(driver.enabledHistory.map(\.displayID), [1, 20])
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [false, false, true])
    }

    func testWakingFromSleepAutomaticallyReEnablesTurnedOffDisplays() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        coordinator.setDisplayEnabled(20, enabled: false)
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, false, true])

        coordinator.handleSystemWake()

        XCTAssertEqual(driver.enabledHistory.map(\.displayID), [20, 20])
        XCTAssertEqual(driver.enabledHistory.map(\.enabled), [false, true])
        XCTAssertTrue(driver.fetchOnlineDisplays().contains(where: { $0.displayID == 20 }))
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, true, true])
        XCTAssertFalse(coordinator.hasDisconnectedDisplays)
    }

    func testQuittingAppAutomaticallyReEnablesTurnedOffDisplaysAndResetsGammaBeforeTermination() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        coordinator.setDisplayEnabled(1, enabled: false)
        coordinator.setDisplayEnabled(20, enabled: false)
        XCTAssertFalse(driver.didResetSoftwareGamma)

        coordinator.handleAppWillTerminate()

        XCTAssertEqual(driver.enabledHistory.map(\.displayID), [1, 20, 1, 20])
        XCTAssertEqual(driver.enabledHistory.map(\.enabled), [false, false, true, true])
        XCTAssertEqual(
            Set(driver.fetchOnlineDisplays().map(\.displayID)),
            [1, 20, 30]
        )
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, true, true])
        XCTAssertFalse(coordinator.hasDisconnectedDisplays)
        XCTAssertTrue(driver.didResetSoftwareGamma)
    }

    func testPersistsBrightnessPerDisplayAcrossHotplugAndAppRestarts() {
        let store = InMemoryBrightnessStore()
        let driver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
                RawDisplayInfo(
                    displayID: 20,
                    name: "DELL P2217H",
                    isBuiltIn: false,
                    isMain: false,
                    vendorID: 0x10AC,
                    modelID: 0xD0B3,
                    serialNumber: 0x12345678
                ),
                RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
            ],
            unsupportedDDCDisplayIDs: [30]
        )

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: store,
            ddcThrottleInterval: 0,
            writeScheduler: ImmediateBrightnessWriteScheduler()
        )
        coordinator.setBrightness(1, level: 0.70)
        coordinator.setBrightness(20, level: 0.45)
        coordinator.setBrightness(30, level: 0.0)

        // Simulate hotplug: DELL P2217H is unplugged, then reconnected on a new displayID with hardware reset to 100%
        driver.onlineDisplays = [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ]
        coordinator.handleDisplayReconfiguration()

        driver.brightnessReadings[25] = BrightnessReading(level: 1.0, backend: .hardwareDDC)
        driver.onlineDisplays = [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(
                displayID: 25,
                name: "DELL P2217H",
                isBuiltIn: false,
                isMain: false,
                vendorID: 0x10AC,
                modelID: 0xD0B3,
                serialNumber: 0x12345678
            ),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ]
        coordinator.handleDisplayReconfiguration()

        let hotpluggedDell = coordinator.displays.first(where: { $0.displayID == 25 })
        XCTAssertEqual(hotpluggedDell?.brightness, 0.45)
        XCTAssertEqual(hotpluggedDell?.brightnessPercentage, 45)
        XCTAssertEqual(driver.brightnessReadings[25]?.level, 0.45)

        // Simulate app restart with a fresh driver and the same persisted store.
        // Built-in display reports its live macOS DisplayServices backlight (0.70), while external monitors
        // reset to 1.0 hardware default and must have their persisted brightness restored by the coordinator.
        let relaunchedDriver = FakeDisplayDriver(
            onlineDisplays: [
                RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
                RawDisplayInfo(
                    displayID: 25,
                    name: "DELL P2217H",
                    isBuiltIn: false,
                    isMain: false,
                    vendorID: 0x10AC,
                    modelID: 0xD0B3,
                    serialNumber: 0x12345678
                ),
                RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
            ],
            brightnessReadings: [
                1: BrightnessReading(level: 0.70, backend: .nativeAppleBacklight)
            ],
            unsupportedDDCDisplayIDs: [30]
        )
        let relaunchedCoordinator = DisplayCoordinator(
            driver: relaunchedDriver,
            brightnessStore: store,
            ddcThrottleInterval: 0,
            writeScheduler: ImmediateBrightnessWriteScheduler()
        )

        XCTAssertEqual(relaunchedCoordinator.displays.map(\.brightness), [0.70, 0.45, 0.0])
        XCTAssertEqual(relaunchedCoordinator.displays.map(\.brightnessPercentage), [70, 45, 0])
        XCTAssertEqual(
            relaunchedCoordinator.displays.map(\.brightnessBackend),
            [.nativeAppleBacklight, .hardwareDDC, .softwareGamma]
        )
        XCTAssertEqual(relaunchedDriver.brightnessReadings[1]?.level, 0.70)
        XCTAssertEqual(relaunchedDriver.brightnessReadings[25]?.level, 0.45)
        XCTAssertEqual(relaunchedDriver.brightnessReadings[30]?.level, 0.0)
    }

    func testUserDefaultsBrightnessStoreDistinguishesZeroFromMissingAndClamps() {
        let suiteName = "OpenBetterDisplayTests.Store.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsBrightnessStore(userDefaults: userDefaults)
        XCTAssertNil(store.brightness(forKey: "builtin"))

        store.setBrightness(0.0, forKey: "builtin")
        XCTAssertEqual(store.brightness(forKey: "builtin"), 0.0)

        store.setBrightness(0.62, forKey: "display:20")
        XCTAssertEqual(store.brightness(forKey: "display:20"), 0.62)
    }

    func testQuittingAppResetsSoftwareGammaEvenWhenAllDisplaysAreActive() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        coordinator.handleAppWillTerminate()

        XCTAssertTrue(driver.enabledHistory.isEmpty)
        XCTAssertTrue(driver.didResetSoftwareGamma)
    }

    func testOnlyActiveNonMainDisplaysCanBeSetAsMainDisplay() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.map(\.canSetAsMain), [true, true, false])

        // Turn off display 20 — it can no longer be set as Main Display
        coordinator.setDisplayEnabled(20, enabled: false)
        XCTAssertEqual(coordinator.displays.map(\.canSetAsMain), [true, false, false])

        // Attempting to promote the turned-off display or the already-Main display is a no-op
        coordinator.setMainDisplay(20)
        coordinator.setMainDisplay(30)
        XCTAssertTrue(driver.mainDisplayHistory.isEmpty)
        XCTAssertEqual(coordinator.displays.map(\.isMain), [false, false, true])

        // Promoting active non-main Built-in Display succeeds and flips canSetAsMain
        coordinator.setMainDisplay(1)
        XCTAssertEqual(driver.mainDisplayHistory, [1])
        XCTAssertEqual(coordinator.displays.map(\.isMain), [true, false, false])
        XCTAssertEqual(coordinator.displays.map(\.canSetAsMain), [false, false, true])
    }

    func testReportsToggleLockReasonForMainDisplayAndLastActiveDisplay() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertNil(coordinator.toggleLockReason(for: 1))
        XCTAssertEqual(coordinator.toggleLockReason(for: 20), .mainDisplay)

        // Turn off Built-in Display — now DELL P2217H is the last active display,
        // while Built-in Display is unlocked so it can be toggled back ON.
        coordinator.setDisplayEnabled(1, enabled: false)
        XCTAssertNil(coordinator.toggleLockReason(for: 1))
        XCTAssertEqual(coordinator.toggleLockReason(for: 20), .lastActiveDisplay)
    }

    func testExternallyReEnabledDisplayReconcilesBackToEnabledOnReconfiguration() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        coordinator.setDisplayEnabled(20, enabled: false)
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, false, true])

        // Simulate macOS externally re-enabling display 20 (e.g. cable replug or System Settings)
        driver.onlineDisplays.append(
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false, isActive: true)
        )
        coordinator.handleDisplayReconfiguration()

        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, true, true])
        XCTAssertFalse(coordinator.hasDisconnectedDisplays)
    }

    func testDriverFailureKeepsDisplayStateConsistentAndAllowsReconnectAllToRecoverOtherDisplays() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        // If turning off display 20 fails at the OS level, it remains enabled
        driver.failingEnableDisplayIDs = [20]
        coordinator.setDisplayEnabled(20, enabled: false)
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, true, true])
        XCTAssertFalse(coordinator.hasDisconnectedDisplays)

        // Turn off both display 1 and display 20 successfully
        driver.failingEnableDisplayIDs = []
        coordinator.setDisplayEnabled(1, enabled: false)
        coordinator.setDisplayEnabled(20, enabled: false)
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [false, false, true])

        // If re-enabling display 1 fails during Reconnect All, display 20 is still re-enabled
        driver.failingEnableDisplayIDs = [1]
        coordinator.reconnectAllDisplays()

        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [false, true, true])
        XCTAssertTrue(coordinator.hasDisconnectedDisplays)
    }

    func testRetainsHumanReadableNameWhenOSReportsDisconnectedDisplayAsInactiveWithDegradedMetadata() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        coordinator.setDisplayEnabled(20, enabled: false)

        // Simulate SkyLight still returning display 20 as inactive with empty/fallback name
        driver.onlineDisplays.append(
            RawDisplayInfo(displayID: 20, name: "", isBuiltIn: false, isMain: false, isActive: false)
        )
        coordinator.handleDisplayReconfiguration()

        XCTAssertEqual(coordinator.displays.map(\.name), ["Built-in Display", "DELL P2217H", "DELL U2725QE"])
        XCTAssertEqual(coordinator.displays.map(\.isEnabled), [true, false, true])
    }

    func testExpandedSectionsActAsSingleOpenAccordionAcrossDisplaysAndSections() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertNil(coordinator.expandedSection)

        // Expand Display Mode on display 20
        coordinator.toggleExpandedSection(.displayMode(20))
        XCTAssertEqual(coordinator.expandedSection, .displayMode(20))

        // Expanding Set as Main Display on the same display collapses Display Mode
        coordinator.toggleExpandedSection(.mainDisplay(20))
        XCTAssertEqual(coordinator.expandedSection, .mainDisplay(20))

        // Expanding Display Mode on another Enabled Display (including Main Display) collapses previous section
        coordinator.toggleExpandedSection(.displayMode(30))
        XCTAssertEqual(coordinator.expandedSection, .displayMode(30))

        // Clicking the already-expanded section collapses it
        coordinator.toggleExpandedSection(.displayMode(30))
        XCTAssertNil(coordinator.expandedSection)

        // Disconnected Display cannot expand Display Mode or Set as Main Display
        coordinator.setDisplayEnabled(20, enabled: false)
        coordinator.toggleExpandedSection(.displayMode(20))
        XCTAssertNil(coordinator.expandedSection)
        coordinator.toggleExpandedSection(.mainDisplay(20))
        XCTAssertNil(coordinator.expandedSection)
    }

    func testSettingMainDisplayRequestsPopoverCloseBeforeCallingDriverAndCollapsesExpandedSection() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        var closeRequestsBeforeDriverCall = 0
        var totalCloseRequests = 0
        coordinator.onRequestPopoverClose = {
            totalCloseRequests += 1
            if driver.mainDisplayHistory.isEmpty {
                closeRequestsBeforeDriverCall += 1
            }
        }

        coordinator.toggleExpandedSection(.mainDisplay(20))
        XCTAssertEqual(coordinator.expandedSection, .mainDisplay(20))

        // Setting DELL P2217H as Main Display must close the popover before driver.setMainDisplay runs
        coordinator.setMainDisplay(20)
        XCTAssertEqual(totalCloseRequests, 1)
        XCTAssertEqual(closeRequestsBeforeDriverCall, 1)
        XCTAssertNil(coordinator.expandedSection)
        XCTAssertEqual(driver.mainDisplayHistory, [20])
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 20 })?.isMain, true)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.isMain, false)

        // No-op Main Display calls (already Main or Disconnected Display) must not request closing popover
        coordinator.setMainDisplay(20)
        coordinator.setDisplayEnabled(30, enabled: false)
        coordinator.setMainDisplay(30)
        coordinator.setDisplayEnabled(30, enabled: true)
        XCTAssertEqual(totalCloseRequests, 1)
    }

    func testExpandedSectionCollapsesOnDisconnectOrUnplug() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        // Expanding Display Mode on DELL P2217H then turning it off auto-collapses the section
        coordinator.toggleExpandedSection(.displayMode(20))
        XCTAssertEqual(coordinator.expandedSection, .displayMode(20))
        coordinator.setDisplayEnabled(20, enabled: false)
        XCTAssertNil(coordinator.expandedSection)

        // Expanding DELL U2725QE then physically unplugging it auto-collapses the section
        coordinator.toggleExpandedSection(.mainDisplay(30))
        XCTAssertEqual(coordinator.expandedSection, .mainDisplay(30))
        driver.onlineDisplays = [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: true)
        ]
        coordinator.handleDisplayReconfiguration()
        XCTAssertNil(coordinator.expandedSection)
    }

    func testPopoverCloseCollapsesAnyExpandedSection() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: true)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.map(\.isMain), [true])

        coordinator.toggleExpandedSection(.displayMode(1))
        XCTAssertEqual(coordinator.expandedSection, .displayMode(1))

        coordinator.handlePopoverDidClose()
        XCTAssertNil(coordinator.expandedSection)
    }

    func testDerivesDynamicFilterChipsAndTracksActiveRefreshRateAndColorDepthWhileUncustomized() {
        let modes: [RawDisplayMode] = [
            // Sub-720p & stretched modes should not contribute filter chips
            RawDisplayMode(
                modeID: 1,
                width: 960,
                height: 540,
                pixelWidth: 1920,
                pixelHeight: 1080,
                refreshRate: 24.0,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 2,
                width: 1280,
                height: 1024,
                pixelWidth: 1280,
                pixelHeight: 1024,
                refreshRate: 75.0,
                bitsPerSample: 8,
                isStretched: true
            ),
            // Safe >= 720p modes covering integer, Variable Refresh Rate, NTSC, 10bit/8bit, HiDPI/LoDPI, and multiple aspect ratios
            RawDisplayMode(
                modeID: 10,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 120.0,
                bitsPerSample: 10,
                minRefreshRate: 48.0,
                isVariableRefreshRate: true
            ),
            RawDisplayMode(
                modeID: 11,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 12,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 120.0,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 13,
                width: 3840,
                height: 2160,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 14,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 59.94,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 15,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 59.94,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 16,
                width: 1600,
                height: 1200,
                pixelWidth: 3200,
                pixelHeight: 2400,
                refreshRate: 120.0,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 17,
                width: 2560,
                height: 1080,
                pixelWidth: 2560,
                pixelHeight: 1080,
                refreshRate: 60.0,
                bitsPerSample: 8
            )
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                vendorID: 0x10AC,
                modelID: 0xD0B3,
                serialNumber: 0xABCD_1234,
                currentModeID: 12,
                modes: modes
            )
        ])

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            modeFilterStore: InMemoryDisplayModeFilterStore()
        )

        guard let initialDisplay = coordinator.displays.first else {
            XCTFail("Expected display")
            return
        }

        // All safe >= 720p modes stay in availableModes
        XCTAssertEqual(initialDisplay.availableModes.map(\.modeID), [13, 10, 12, 14, 17, 11, 15, 16])

        // Filter chips derive exclusively from safe >= 720p modes (no 24Hz or 5:4/75Hz from excluded modes)
        XCTAssertEqual(initialDisplay.modeFilterState.availableOptions.aspectRatios, ["4:3", "16:9", "21:9"])
        XCTAssertEqual(initialDisplay.modeFilterState.availableOptions.refreshRates, ["48–120Hz", "120Hz", "60Hz", "59.94Hz"])
        XCTAssertEqual(initialDisplay.modeFilterState.availableOptions.colorDepths, [10, 8])
        XCTAssertEqual(initialDisplay.modeFilterState.availableOptions.scalingTiers, [.hiDPI, .loDPI])

        // Uncustomized default tracks native aspect (16:9), active rate (120Hz), active color depth (10bit), preferred tier (HiDPI)
        XCTAssertFalse(initialDisplay.modeFilterState.isCustomized)
        XCTAssertEqual(
            initialDisplay.modeFilterState.activeCriteria,
            DisplayModeFilterCriteria(
                aspectRatios: ["16:9"],
                refreshRates: ["120Hz"],
                colorDepths: [10],
                scalingTiers: [.hiDPI]
            )
        )
        XCTAssertEqual(initialDisplay.filteredModes.map(\.modeID), [12, 11])

        // Switching to Native Mode (LoDPI at 120Hz 10bit) keeps preferred HiDPI tier and native aspect ratio
        coordinator.selectDisplayMode(30, modeID: 13)
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.activeCriteria.scalingTiers, [.hiDPI])
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.activeCriteria.aspectRatios, ["16:9"])
        XCTAssertEqual(coordinator.displays.first?.filteredModes.map(\.modeID), [12, 11])

        // Switching to a 59.94Hz 8bit mode updates active refresh rate & color depth while keeping 16:9 and HiDPI
        coordinator.selectDisplayMode(30, modeID: 14)
        XCTAssertEqual(
            coordinator.displays.first?.modeFilterState.activeCriteria,
            DisplayModeFilterCriteria(
                aspectRatios: ["16:9"],
                refreshRates: ["59.94Hz"],
                colorDepths: [8],
                scalingTiers: [.hiDPI]
            )
        )
        XCTAssertEqual(coordinator.displays.first?.filteredModes.map(\.modeID), [14, 15])

        // Switching to Variable Refresh Rate (48–120Hz, 10bit) updates dynamic filter to 48–120Hz & 10bit
        coordinator.selectDisplayMode(30, modeID: 10)
        XCTAssertEqual(
            coordinator.displays.first?.modeFilterState.activeCriteria,
            DisplayModeFilterCriteria(
                aspectRatios: ["16:9"],
                refreshRates: ["48–120Hz"],
                colorDepths: [10],
                scalingTiers: [.hiDPI]
            )
        )
        XCTAssertEqual(coordinator.displays.first?.filteredModes.map(\.modeID), [10])
    }

    func testFilterChipPlainClickSoloSelectsWithinGroupWhileShiftClickMultiSelectsAcrossChips() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 100,
                width: 3840,
                height: 2160,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 101,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 120.0,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 102,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 103,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 60.0,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 104,
                width: 2560,
                height: 1440,
                pixelWidth: 2560,
                pixelHeight: 1440,
                refreshRate: 60.0,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 105,
                width: 1600,
                height: 1200,
                pixelWidth: 3200,
                pixelHeight: 2400,
                refreshRate: 60.0,
                bitsPerSample: 10
            )
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                currentModeID: 101,
                modes: modes
            ),
            RawDisplayInfo(
                displayID: 20,
                name: "DELL P2217H",
                isBuiltIn: false,
                isMain: false,
                isActive: false,
                currentModeID: 200,
                modes: [
                    RawDisplayMode(
                        modeID: 200,
                        width: 1920,
                        height: 1080,
                        pixelWidth: 1920,
                        pixelHeight: 1080,
                        refreshRate: 60.0,
                        isNative: true
                    )
                ]
            )
        ])

        let store = InMemoryDisplayModeFilterStore()
        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            modeFilterStore: store
        )

        let display30 = { coordinator.displays.first(where: { $0.displayID == 30 }) }

        XCTAssertEqual(display30()?.filteredModes.map(\.modeID), [101, 102])

        // Plain click selects only 60Hz within refresh rates while preserving 16:9, 10bit, HiDPI
        coordinator.selectDisplayModeFilterChip(30, chip: .refreshRate("60Hz"), multiSelect: false)
        XCTAssertEqual(display30()?.modeFilterState.isCustomized, true)
        XCTAssertEqual(
            display30()?.modeFilterState.activeCriteria,
            DisplayModeFilterCriteria(
                aspectRatios: ["16:9"],
                refreshRates: ["60Hz"],
                colorDepths: [10],
                scalingTiers: [.hiDPI]
            )
        )
        XCTAssertEqual(display30()?.filteredModes.map(\.modeID), [103])

        // Shift+click adds 120Hz alongside 60Hz
        coordinator.selectDisplayModeFilterChip(30, chip: .refreshRate("120Hz"), multiSelect: true)
        XCTAssertEqual(display30()?.modeFilterState.activeCriteria.refreshRates, ["60Hz", "120Hz"])
        XCTAssertEqual(display30()?.filteredModes.map(\.modeID), [101, 103, 102])

        // Shift+click adds 4:3 alongside 16:9, and LoDPI + 8bit
        coordinator.selectDisplayModeFilterChip(30, chip: .aspectRatio("4:3"), multiSelect: true)
        coordinator.selectDisplayModeFilterChip(30, chip: .scaling(.loDPI), multiSelect: true)
        coordinator.selectDisplayModeFilterChip(30, chip: .colorDepth(8), multiSelect: true)
        XCTAssertEqual(display30()?.filteredModes.map(\.modeID), [100, 101, 103, 104, 102, 105])

        // Plain click on 120Hz solo-selects 120Hz in refresh rates while keeping multi-selected aspect, depth, and scaling
        coordinator.selectDisplayModeFilterChip(30, chip: .refreshRate("120Hz"), multiSelect: false)
        XCTAssertEqual(display30()?.modeFilterState.activeCriteria.refreshRates, ["120Hz"])
        XCTAssertEqual(display30()?.modeFilterState.activeCriteria.aspectRatios, ["16:9", "4:3"])
        XCTAssertEqual(display30()?.filteredModes.map(\.modeID), [100, 101, 102])

        // Shift+clicking the sole selected chip in a group toggles it off, leaving that group unrestricted
        coordinator.selectDisplayModeFilterChip(30, chip: .refreshRate("120Hz"), multiSelect: true)
        XCTAssertEqual(display30()?.modeFilterState.activeCriteria.refreshRates, [])
        XCTAssertEqual(display30()?.filteredModes.map(\.modeID), [100, 101, 103, 104, 102, 105])

        // Disconnected Display ignores chip toggles
        coordinator.selectDisplayModeFilterChip(20, chip: .refreshRate("60Hz"), multiSelect: false)
        XCTAssertNil(store.modeFilter(forKey: "display:20"))
    }

    func testShowAllResetDefaultAndSelectingFilteredOutSafeModes() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 100,
                width: 3840,
                height: 2160,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 101,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 120.0,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 102,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 103,
                width: 2560,
                height: 1440,
                pixelWidth: 2560,
                pixelHeight: 1440,
                refreshRate: 60.0,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 104,
                width: 1600,
                height: 1200,
                pixelWidth: 1600,
                pixelHeight: 1200,
                refreshRate: 60.0,
                bitsPerSample: 8
            )
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                currentModeID: 101,
                modes: modes
            )
        ])

        let store = InMemoryDisplayModeFilterStore()
        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            modeFilterStore: store
        )

        XCTAssertEqual(coordinator.displays.first?.filteredModes.map(\.modeID), [101, 102])

        // Show All reveals all safe >= 720p modes
        coordinator.showAllDisplayModes(30)
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.isCustomized, true)
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.isShowingAll, true)
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.activeCriteria, .unrestricted)
        XCTAssertEqual(
            coordinator.displays.first?.filteredModes.map(\.modeID),
            coordinator.displays.first?.availableModes.map(\.modeID)
        )

        // Restricting a single group after Show All filters only by that group
        coordinator.selectDisplayModeFilterChip(30, chip: .colorDepth(8), multiSelect: false)
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.isShowingAll, false)
        XCTAssertEqual(coordinator.displays.first?.filteredModes.map(\.modeID), [103, 104])

        // Selecting a safe mode that is currently filtered out (Native 100 or Default 102) still succeeds
        coordinator.selectDisplayMode(30, modeID: 100)
        XCTAssertEqual(driver.setModeHistory.last?.modeID, 100)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 100)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "3840x2160")
        // Custom filter stays pinned on 8bit across the mode switch
        XCTAssertEqual(coordinator.displays.first?.filteredModes.map(\.modeID), [103, 104])

        // Reset Default clears custom filter and tracks current mode (120Hz, 10bit) + native aspect (16:9) + preferred tier (HiDPI)
        coordinator.resetDisplayModeFilter(30)
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.isCustomized, false)
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.isShowingAll, false)
        XCTAssertEqual(
            coordinator.displays.first?.modeFilterState.activeCriteria,
            DisplayModeFilterCriteria(
                aspectRatios: ["16:9"],
                refreshRates: ["120Hz"],
                colorDepths: [10],
                scalingTiers: [.hiDPI]
            )
        )
        XCTAssertEqual(coordinator.displays.first?.filteredModes.map(\.modeID), [101, 102])
        XCTAssertNil(store.modeFilter(forKey: "display:30"))
    }

    func testPersistsCustomDisplayModeFilterPerPhysicalDisplayAcrossRefreshRateChangesAndRestarts() {
        let builtInModes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 10,
                width: 1512,
                height: 982,
                pixelWidth: 3024,
                pixelHeight: 1964,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 11,
                width: 1512,
                height: 982,
                pixelWidth: 3024,
                pixelHeight: 1964,
                refreshRate: 59.94,
                bitsPerSample: 10
            )
        ]

        let dellModes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 30,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 120.0,
                bitsPerSample: 10
            ),
            RawDisplayMode(
                modeID: 31,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 32,
                width: 2560,
                height: 1440,
                pixelWidth: 2560,
                pixelHeight: 1440,
                refreshRate: 60.0,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 33,
                width: 1920,
                height: 1080,
                pixelWidth: 1920,
                pixelHeight: 1080,
                refreshRate: 60.0,
                bitsPerSample: 8
            )
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 1,
                name: "Built-in Display",
                isBuiltIn: true,
                isMain: false,
                currentModeID: 10,
                modes: builtInModes
            ),
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                vendorID: 0x10AC,
                modelID: 0xD0B3,
                serialNumber: 0x0001_0002,
                currentModeID: 30,
                modes: dellModes
            )
        ])

        let store = InMemoryDisplayModeFilterStore()
        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            modeFilterStore: store
        )

        // Customize DELL U2725QE to 60Hz + 8bit + LoDPI; keep Built-in Display uncustomized
        coordinator.selectDisplayModeFilterChip(30, chip: .refreshRate("60Hz"), multiSelect: false)
        coordinator.selectDisplayModeFilterChip(30, chip: .colorDepth(8), multiSelect: false)
        coordinator.selectDisplayModeFilterChip(30, chip: .scaling(.loDPI), multiSelect: false)

        // External refresh-rate switch + reconfiguration keeps DELL custom filter, while Built-in tracks 59.94Hz dynamically
        driver.onlineDisplays[0].currentModeID = 11
        driver.onlineDisplays[1].currentModeID = 31
        coordinator.handleDisplayReconfiguration()

        let builtInAfterSwitch = coordinator.displays.first(where: { $0.displayID == 1 })
        let dellAfterSwitch = coordinator.displays.first(where: { $0.displayID == 30 })
        XCTAssertEqual(builtInAfterSwitch?.modeFilterState.isCustomized, false)
        XCTAssertEqual(builtInAfterSwitch?.modeFilterState.activeCriteria.refreshRates, ["59.94Hz"])
        XCTAssertEqual(dellAfterSwitch?.modeFilterState.isCustomized, true)
        XCTAssertEqual(dellAfterSwitch?.filteredModes.map(\.modeID), [32, 33])

        // Simulate app relaunch where macOS reassigned DELL displayID from 30 to 45 (same physical hardware serial)
        let relaunchedDriver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 1,
                name: "Built-in Display",
                isBuiltIn: true,
                isMain: false,
                currentModeID: 10,
                modes: builtInModes
            ),
            RawDisplayInfo(
                displayID: 45,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                vendorID: 0x10AC,
                modelID: 0xD0B3,
                serialNumber: 0x0001_0002,
                currentModeID: 31,
                modes: dellModes
            )
        ])

        let relaunchedCoordinator = DisplayCoordinator(
            driver: relaunchedDriver,
            brightnessStore: InMemoryBrightnessStore(),
            modeFilterStore: store
        )

        let relaunchedBuiltIn = relaunchedCoordinator.displays.first(where: { $0.displayID == 1 })
        let relaunchedDell = relaunchedCoordinator.displays.first(where: { $0.displayID == 45 })
        XCTAssertEqual(relaunchedBuiltIn?.modeFilterState.isCustomized, false)
        XCTAssertEqual(relaunchedBuiltIn?.modeFilterState.activeCriteria.refreshRates, ["120Hz"])
        XCTAssertEqual(relaunchedDell?.modeFilterState.isCustomized, true)
        XCTAssertEqual(
            relaunchedDell?.modeFilterState.activeCriteria,
            DisplayModeFilterCriteria(
                aspectRatios: ["16:9"],
                refreshRates: ["60Hz"],
                colorDepths: [8],
                scalingTiers: [.loDPI]
            )
        )
        XCTAssertEqual(relaunchedDell?.filteredModes.map(\.modeID), [32, 33])

        // Reset Default on relaunched display clears persistence so next launch starts uncustomized
        relaunchedCoordinator.resetDisplayModeFilter(45)
        XCTAssertEqual(relaunchedCoordinator.displays.first(where: { $0.displayID == 45 })?.modeFilterState.isCustomized, false)
        XCTAssertNil(store.modeFilter(forKey: "hardware:10AC:D0B3:00010002"))
    }

    func testUserDefaultsDisplayModeFilterStoreRoundTripsCustomAndShowAllFiltersAndClearsOnReset() throws {
        let suiteName = "OpenBetterDisplayTests.ModeFilter.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsDisplayModeFilterStore(userDefaults: defaults)
        XCTAssertNil(store.modeFilter(forKey: "hardware:10AC:D0B3:00010002"))

        let custom = DisplayModeFilterCriteria(
            aspectRatios: ["16:9", "16:10"],
            refreshRates: ["48–120Hz", "59.94Hz"],
            colorDepths: [10],
            scalingTiers: [.hiDPI]
        )
        store.setModeFilter(custom, forKey: "hardware:10AC:D0B3:00010002")
        XCTAssertEqual(store.modeFilter(forKey: "hardware:10AC:D0B3:00010002"), custom)

        // Show All (.unrestricted) must still persist distinctly from nil (uncustomized)
        store.setModeFilter(.unrestricted, forKey: "builtin")
        XCTAssertEqual(store.modeFilter(forKey: "builtin"), .unrestricted)

        // Reset Default removes persisted entry
        store.setModeFilter(nil, forKey: "hardware:10AC:D0B3:00010002")
        XCTAssertNil(store.modeFilter(forKey: "hardware:10AC:D0B3:00010002"))
        XCTAssertEqual(store.modeFilter(forKey: "builtin"), .unrestricted)
    }

    func testDisplayModeFilterPanelExpansionLifecycleMatchesAccordionDisconnectAndPopoverClose() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true)
        ])

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            modeFilterStore: InMemoryDisplayModeFilterStore()
        )
        XCTAssertNil(coordinator.expandedDisplayModeFilterDisplayID)

        // Opening filter for an Enabled Display expands both its Display Mode section and Filter panel
        coordinator.toggleDisplayModeFilter(30)
        XCTAssertEqual(coordinator.expandedSection, .displayMode(30))
        XCTAssertEqual(coordinator.expandedDisplayModeFilterDisplayID, 30)

        // Toggling again collapses Filter panel while keeping Display Mode section open
        coordinator.toggleDisplayModeFilter(30)
        XCTAssertEqual(coordinator.expandedSection, .displayMode(30))
        XCTAssertNil(coordinator.expandedDisplayModeFilterDisplayID)

        // Switching expandedSection to another section or closing Display Mode auto-collapses Filter panel
        coordinator.toggleDisplayModeFilter(30)
        XCTAssertEqual(coordinator.expandedDisplayModeFilterDisplayID, 30)
        coordinator.toggleExpandedSection(.mainDisplay(30))
        XCTAssertNil(coordinator.expandedDisplayModeFilterDisplayID)

        // Disconnecting the display collapses both expandedSection and Filter panel
        coordinator.toggleDisplayModeFilter(20)
        XCTAssertEqual(coordinator.expandedDisplayModeFilterDisplayID, 20)
        coordinator.setDisplayEnabled(20, enabled: false)
        XCTAssertNil(coordinator.expandedSection)
        XCTAssertNil(coordinator.expandedDisplayModeFilterDisplayID)

        // Disconnected Display ignores toggleDisplayModeFilter
        coordinator.toggleDisplayModeFilter(20)
        XCTAssertNil(coordinator.expandedDisplayModeFilterDisplayID)

        // Popover close collapses Filter panel
        coordinator.toggleDisplayModeFilter(30)
        XCTAssertEqual(coordinator.expandedDisplayModeFilterDisplayID, 30)
        coordinator.handlePopoverDidClose()
        XCTAssertNil(coordinator.expandedDisplayModeFilterDisplayID)
    }

    func testStandard1080pDisplayTracksLoDPIPreferredTierAndHandlesStalePersistedFilterChipsGracefully() {
        let dell1080Modes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 1,
                width: 1920,
                height: 1080,
                pixelWidth: 1920,
                pixelHeight: 1080,
                refreshRate: 75.0,
                isNative: true,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 2,
                width: 1920,
                height: 1080,
                pixelWidth: 1920,
                pixelHeight: 1080,
                refreshRate: 60.0,
                isNative: true,
                bitsPerSample: 8,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 3,
                width: 1600,
                height: 900,
                pixelWidth: 1600,
                pixelHeight: 900,
                refreshRate: 60.0,
                bitsPerSample: 8
            ),
            RawDisplayMode(
                modeID: 4,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 60.0,
                bitsPerSample: 8
            )
        ]

        let store = InMemoryDisplayModeFilterStore(initialFilters: [
            // Stale 120Hz selection on a 75Hz/60Hz-only display falls back to unrestricted refresh rate while keeping LoDPI
            "display:20": DisplayModeFilterCriteria(
                aspectRatios: ["16:9"],
                refreshRates: ["120Hz"],
                colorDepths: [8],
                scalingTiers: [.loDPI]
            )
        ])

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 20,
                name: "DELL P2217H",
                isBuiltIn: false,
                isMain: true,
                currentModeID: 2,
                modes: dell1080Modes
            )
        ])

        let coordinator = DisplayCoordinator(
            driver: driver,
            brightnessStore: InMemoryBrightnessStore(),
            modeFilterStore: store
        )

        XCTAssertEqual(coordinator.displays.first?.filteredModes.map(\.modeID), [1, 2, 3])

        // Resetting returns to uncustomized LoDPI + 60Hz default, then follows 75Hz switch while keeping LoDPI
        coordinator.resetDisplayModeFilter(20)
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.activeCriteria.scalingTiers, [.loDPI])
        XCTAssertEqual(coordinator.displays.first?.filteredModes.map(\.modeID), [2, 3])

        coordinator.selectDisplayMode(20, modeID: 1)
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.activeCriteria.refreshRates, ["75Hz"])
        XCTAssertEqual(coordinator.displays.first?.modeFilterState.activeCriteria.scalingTiers, [.loDPI])
        XCTAssertEqual(coordinator.displays.first?.filteredModes.map(\.modeID), [1])
    }

    func testAssigningCurrentDisplayModeToFavoriteSlotPopulatesDisplayStateAndValidatesSlotBounds() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 101,
                width: 1920,
                height: 1080,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 120.0,
                isNative: true,
                bitsPerSample: 10,
                isDefault: true
            ),
            RawDisplayMode(
                modeID: 102,
                width: 2560,
                height: 1440,
                pixelWidth: 5120,
                pixelHeight: 2880,
                refreshRate: 120.0,
                bitsPerSample: 10
            )
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                vendorID: 0x10AC,
                modelID: 0xD0F1,
                serialNumber: 0xAABBCCDD,
                currentModeID: 102,
                modes: modes
            ),
            RawDisplayInfo(
                displayID: 40,
                name: "DELL P2217H",
                isBuiltIn: false,
                isMain: false,
                isActive: false,
                currentModeID: 101,
                modes: modes
            )
        ])

        let favoriteStore = InMemoryFavoriteModesStore()
        let coordinator = DisplayCoordinator(driver: driver, favoriteModesStore: favoriteStore)

        XCTAssertTrue(coordinator.displays.first(where: { $0.displayID == 30 })?.favoriteModes.isEmpty ?? false)

        coordinator.assignCurrentModeToFavorite(30, slot: 3)
        coordinator.assignCurrentModeToFavorite(30, slot: 1)
        coordinator.assignCurrentModeToFavorite(30, slot: 0)
        coordinator.assignCurrentModeToFavorite(30, slot: 6)
        coordinator.assignCurrentModeToFavorite(40, slot: 1)

        let display30 = coordinator.displays.first(where: { $0.displayID == 30 })
        XCTAssertEqual(display30?.favoriteModes.map(\.slot), [1, 3])
        XCTAssertEqual(display30?.favoriteModes.first?.resolvedMode?.modeID, 102)
        XCTAssertEqual(display30?.favoriteModes.first?.record.width, 2560)
        XCTAssertEqual(display30?.favoriteModes.first?.record.height, 1440)
        XCTAssertEqual(display30?.favoriteModes.first?.record.pixelWidth, 5120)
        XCTAssertEqual(display30?.favoriteModes.first?.record.pixelHeight, 2880)
        XCTAssertEqual(display30?.favoriteModes.first?.record.refreshRate, 120.0)
        XCTAssertEqual(display30?.favoriteModes.first?.record.bitsPerSample, 10)
        XCTAssertTrue(coordinator.displays.first(where: { $0.displayID == 40 })?.favoriteModes.isEmpty ?? false)
    }

    func testAssigningSpecificModeReplacesSlotAndClearingOrRemovingUpdatesFavorites() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 120.0, bitsPerSample: 10),
            RawDisplayMode(
                modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 120.0, bitsPerSample: 10),
            RawDisplayMode(modeID: 103, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0, bitsPerSample: 8)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true, currentModeID: 102, modes: modes)
        ])

        let favoriteStore = InMemoryFavoriteModesStore()
        let coordinator = DisplayCoordinator(driver: driver, favoriteModesStore: favoriteStore)

        // Assign non-current modes without switching active mode
        coordinator.assignFavoriteMode(30, modeID: 101, slot: 2)
        coordinator.assignFavoriteMode(30, modeID: 103, slot: 5)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 102)
        XCTAssertTrue(driver.setModeHistory.isEmpty)
        XCTAssertEqual(coordinator.displays.first?.favoriteModes.map(\.slot), [2, 5])
        XCTAssertEqual(coordinator.displays.first?.favoriteMode(forSlot: 2)?.resolvedMode?.modeID, 101)
        XCTAssertTrue(coordinator.displays.first?.isFavorited(modeID: 101) ?? false)

        // Replace slot 2 with mode 103 and ignore unknown modeID
        coordinator.assignFavoriteMode(30, modeID: 103, slot: 2)
        coordinator.assignFavoriteMode(30, modeID: 999, slot: 4)
        XCTAssertEqual(coordinator.displays.first?.favoriteMode(forSlot: 2)?.resolvedMode?.modeID, 103)
        XCTAssertFalse(coordinator.displays.first?.isFavorited(modeID: 101) ?? true)
        XCTAssertTrue(coordinator.displays.first?.isFavorited(modeID: 103) ?? false)
        XCTAssertNil(coordinator.displays.first?.favoriteMode(forSlot: 4))

        // Removing a mode from Favorites clears every slot pointing to it
        coordinator.removeModeFromFavorites(30, modeID: 103)
        XCTAssertTrue(coordinator.displays.first?.favoriteModes.isEmpty ?? false)

        // Clearing one slot leaves other slots intact
        coordinator.assignFavoriteMode(30, modeID: 101, slot: 1)
        coordinator.assignFavoriteMode(30, modeID: 102, slot: 4)
        coordinator.clearFavoriteMode(30, slot: 1)
        XCTAssertEqual(coordinator.displays.first?.favoriteModes.map(\.slot), [4])
        XCTAssertEqual(coordinator.displays.first?.favoriteMode(forSlot: 4)?.resolvedMode?.modeID, 102)
    }

    func testSelectingFavoriteSlotSwitchesDisplayModeImmediatelyAndPreservesStateOnFailure() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 120.0, bitsPerSample: 10),
            RawDisplayMode(
                modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 120.0, bitsPerSample: 10),
            RawDisplayMode(modeID: 103, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0, bitsPerSample: 8)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true, currentModeID: 101, modes: modes),
            RawDisplayInfo(
                displayID: 40, name: "DELL P2217H", isBuiltIn: false, isMain: false, isActive: false, currentModeID: 101, modes: modes)
        ])
        let favoriteStore = InMemoryFavoriteModesStore()
        let coordinator = DisplayCoordinator(driver: driver, favoriteModesStore: favoriteStore)

        coordinator.assignFavoriteMode(30, modeID: 102, slot: 1)
        coordinator.assignFavoriteMode(30, modeID: 103, slot: 2)

        // Switching to empty slot or disabled display is ignored
        coordinator.selectFavoriteMode(30, slot: 5)
        coordinator.selectFavoriteMode(40, slot: 1)
        XCTAssertTrue(driver.setModeHistory.isEmpty)

        // Switching to slot 1 activates mode 102
        coordinator.selectFavoriteMode(30, slot: 1)
        XCTAssertEqual(driver.setModeHistory.count, 1)
        XCTAssertEqual(driver.setModeHistory.first?.displayID, 30)
        XCTAssertEqual(driver.setModeHistory.first?.modeID, 102)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.currentModeID, 102)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.resolutionLabel, "2560x1440")

        // Clicking an already-active favorite slot does not call driver again
        coordinator.selectFavoriteMode(30, slot: 1)
        XCTAssertEqual(driver.setModeHistory.count, 1)

        // Driver error preserves currentModeID and resolutionLabel
        driver.setDisplayModeError = DisplayDriverError.configurationFailed(-1)
        coordinator.selectFavoriteMode(30, slot: 2)
        XCTAssertEqual(driver.setModeHistory.count, 2)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.currentModeID, 102)
        XCTAssertEqual(coordinator.displays.first(where: { $0.displayID == 30 })?.resolutionLabel, "2560x1440")
    }

    func testFavoriteModesPersistPerPhysicalDisplayAcrossHotplugAndResolveViaAttributeFallbackWhenModeIDShifts() {
        let builtInModes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 12, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120.0, bitsPerSample: 10)
        ]
        let externalModesInitial: [RawDisplayMode] = [
            RawDisplayMode(
                modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 120.0, bitsPerSample: 10),
            RawDisplayMode(
                modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 120.0, bitsPerSample: 10),
            RawDisplayMode(modeID: 103, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0, bitsPerSample: 8)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false, currentModeID: 12, modes: builtInModes),
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                vendorID: 0x10AC,
                modelID: 0xD0F1,
                serialNumber: 0x11223344,
                currentModeID: 101,
                modes: externalModesInitial
            )
        ])

        let favoriteStore = InMemoryFavoriteModesStore()
        let coordinator = DisplayCoordinator(driver: driver, favoriteModesStore: favoriteStore)
        coordinator.assignCurrentModeToFavorite(1, slot: 1)
        coordinator.assignFavoriteMode(30, modeID: 102, slot: 1)
        coordinator.assignFavoriteMode(30, modeID: 103, slot: 2)

        // Simulate hotplug + macOS reassigning modeIDs (102 now points to 1280x720, while 2560x1440 moved to 502)
        // and slot 2's 60Hz 8bit mode temporarily unavailable while 3840x2160 120Hz 10bit is present.
        let externalModesReconnected: [RawDisplayMode] = [
            RawDisplayMode(modeID: 102, width: 1280, height: 720, pixelWidth: 1280, pixelHeight: 720, refreshRate: 60.0, bitsPerSample: 8),
            RawDisplayMode(
                modeID: 501, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 120.0, bitsPerSample: 10),
            RawDisplayMode(
                modeID: 502, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 120.0, bitsPerSample: 10),
            RawDisplayMode(
                modeID: 503, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 120.0, bitsPerSample: 10)
        ]

        let relaunchedDriver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false, currentModeID: 12, modes: builtInModes),
            RawDisplayInfo(
                displayID: 35,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                vendorID: 0x10AC,
                modelID: 0xD0F1,
                serialNumber: 0x11223344,
                currentModeID: 501,
                modes: externalModesReconnected
            )
        ])

        let relaunchedCoordinator = DisplayCoordinator(driver: relaunchedDriver, favoriteModesStore: favoriteStore)
        let builtIn = relaunchedCoordinator.displays.first(where: { $0.displayID == 1 })
        let reconnectedExternal = relaunchedCoordinator.displays.first(where: { $0.displayID == 35 })

        XCTAssertEqual(builtIn?.favoriteModes.map(\.slot), [1])
        XCTAssertEqual(builtIn?.favoriteMode(forSlot: 1)?.resolvedMode?.modeID, 12)

        XCTAssertEqual(reconnectedExternal?.favoriteModes.map(\.slot), [1, 2])
        XCTAssertEqual(reconnectedExternal?.favoriteMode(forSlot: 1)?.resolvedMode?.modeID, 502)
        XCTAssertTrue(reconnectedExternal?.favoriteMode(forSlot: 1)?.isAvailable ?? false)
        XCTAssertNil(reconnectedExternal?.favoriteMode(forSlot: 2)?.resolvedMode)
        XCTAssertFalse(reconnectedExternal?.favoriteMode(forSlot: 2)?.isAvailable ?? true)

        relaunchedCoordinator.selectFavoriteMode(35, slot: 1)
        XCTAssertEqual(relaunchedDriver.setModeHistory.last?.displayID, 35)
        XCTAssertEqual(relaunchedDriver.setModeHistory.last?.modeID, 502)
        XCTAssertEqual(relaunchedCoordinator.displays.first(where: { $0.displayID == 35 })?.currentModeID, 502)

        // When 3840x2160 @ 60Hz 8bit returns on modeID 603, slot 2 resolves again without user reassignment
        relaunchedDriver.onlineDisplays[1].modes.append(
            RawDisplayMode(modeID: 603, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0, bitsPerSample: 8)
        )
        relaunchedCoordinator.handleDisplayReconfiguration()
        let updatedExternal = relaunchedCoordinator.displays.first(where: { $0.displayID == 35 })
        XCTAssertEqual(updatedExternal?.favoriteMode(forSlot: 2)?.resolvedMode?.modeID, 603)
    }

    func testUserDefaultsFavoriteModesStorePersistsAndClearsSlotsPerDisplayKey() {
        let suiteName = "OpenBetterDisplayTests.Favorites.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsFavoriteModesStore(userDefaults: userDefaults)
        XCTAssertTrue(store.favoriteModes(forKey: "builtin").isEmpty)

        let slot1 = FavoriteModeRecord(
            modeID: 102,
            width: 2560,
            height: 1440,
            pixelWidth: 5120,
            pixelHeight: 2880,
            refreshRate: 120.0,
            bitsPerSample: 10
        )
        let slot5 = FavoriteModeRecord(
            modeID: 103,
            width: 3840,
            height: 2160,
            pixelWidth: 3840,
            pixelHeight: 2160,
            refreshRate: 59.94,
            bitsPerSample: 8
        )
        store.setFavoriteModes([0: slot1, 1: slot1, 5: slot5, 6: slot5], forKey: "hardware:10AC:D0F1:11223344")

        let reloadedStore = UserDefaultsFavoriteModesStore(userDefaults: userDefaults)
        XCTAssertTrue(reloadedStore.favoriteModes(forKey: "builtin").isEmpty)
        let loaded = reloadedStore.favoriteModes(forKey: "hardware:10AC:D0F1:11223344")
        XCTAssertEqual(loaded, [1: slot1, 5: slot5])

        reloadedStore.setFavoriteModes([:], forKey: "hardware:10AC:D0F1:11223344")
        XCTAssertTrue(store.favoriteModes(forKey: "hardware:10AC:D0F1:11223344").isEmpty)
    }

    func testManageFavoritesTogglesInsideDisplayModeAndResetsWhenSectionOrPopoverCloses() {
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: false),
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true),
            RawDisplayInfo(displayID: 40, name: "DELL P2217H", isBuiltIn: false, isMain: false, isActive: false)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        coordinator.toggleManageFavorites(for: 40)
        XCTAssertNil(coordinator.managingFavoritesDisplayID)

        coordinator.toggleManageFavorites(for: 30)
        XCTAssertEqual(coordinator.expandedSection, .displayMode(30))
        XCTAssertEqual(coordinator.managingFavoritesDisplayID, 30)

        coordinator.toggleManageFavorites(for: 30)
        XCTAssertNil(coordinator.managingFavoritesDisplayID)
        XCTAssertEqual(coordinator.expandedSection, .displayMode(30))

        // Opening another section collapses Manage...
        coordinator.toggleManageFavorites(for: 30)
        XCTAssertEqual(coordinator.managingFavoritesDisplayID, 30)
        coordinator.toggleExpandedSection(.mainDisplay(30))
        XCTAssertNil(coordinator.managingFavoritesDisplayID)

        // Closing popover resets Manage...
        coordinator.toggleManageFavorites(for: 1)
        XCTAssertEqual(coordinator.managingFavoritesDisplayID, 1)
        coordinator.handlePopoverDidClose()
        XCTAssertNil(coordinator.managingFavoritesDisplayID)

        // Disconnecting display resets Manage...
        coordinator.toggleManageFavorites(for: 1)
        XCTAssertEqual(coordinator.managingFavoritesDisplayID, 1)
        coordinator.setDisplayEnabled(1, enabled: false)
        XCTAssertNil(coordinator.managingFavoritesDisplayID)
    }
}

@MainActor
private final class ManualBrightnessWriteScheduler: BrightnessWriteScheduling {
    private final class Token: BrightnessWriteCancellable {
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

    private var currentTime: TimeInterval = 0
    private var scheduledTokens: [Token] = []
    private let deferWriteCompletions: Bool
    private var queuedWrites: [(work: @Sendable () -> BrightnessBackendUsed, completion: @MainActor (BrightnessBackendUsed) -> Void)] = []

    init(deferWriteCompletions: Bool = false) {
        self.deferWriteCompletions = deferWriteCompletions
    }

    var pendingWriteCount: Int {
        queuedWrites.count
    }

    func now() -> TimeInterval {
        currentTime
    }

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> BrightnessWriteCancellable {
        let token = Token(fireTime: currentTime + max(0, delay), action: action)
        scheduledTokens.append(token)
        return token
    }

    func performWrite(
        _ work: @escaping @Sendable () -> BrightnessBackendUsed,
        completion: @escaping @MainActor (BrightnessBackendUsed) -> Void
    ) {
        if deferWriteCompletions {
            queuedWrites.append((work: work, completion: completion))
        } else {
            completion(work())
        }
    }

    func completeNextWrite() {
        guard !queuedWrites.isEmpty else { return }
        let next = queuedWrites.removeFirst()
        next.completion(next.work())
    }

    func advance(by interval: TimeInterval) {
        currentTime += max(0, interval)
        while true {
            let ready =
                scheduledTokens
                .filter { !$0.isCancelled && $0.fireTime <= currentTime + 1e-9 }
                .sorted { $0.fireTime < $1.fireTime }
            guard let next = ready.first else { break }
            scheduledTokens.removeAll { $0 === next }
            next.action()
        }
    }
}
