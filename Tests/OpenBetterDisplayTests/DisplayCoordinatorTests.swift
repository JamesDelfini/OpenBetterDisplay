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

        // Simulate app restart with a fresh driver and the same persisted store
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
}

@MainActor
private final class ManualBrightnessWriteScheduler: BrightnessWriteScheduling {
    private final class Token {
        let fireTime: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false

        init(fireTime: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.fireTime = fireTime
            self.action = action
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

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyObject {
        let token = Token(fireTime: currentTime + max(0, delay), action: action)
        scheduledTokens.append(token)
        return token
    }

    func cancel(_ token: AnyObject) {
        if let typed = token as? Token {
            typed.isCancelled = true
        }
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
            let ready = scheduledTokens
                .filter { !$0.isCancelled && $0.fireTime <= currentTime + 1e-9 }
                .sorted { $0.fireTime < $1.fireTime }
            guard let next = ready.first else { break }
            scheduledTokens.removeAll { $0 === next }
            next.action()
        }
    }
}
