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
}
