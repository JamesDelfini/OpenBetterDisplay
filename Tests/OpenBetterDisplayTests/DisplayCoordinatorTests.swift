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

    func testFiltersModesToNativeAspectRatioAndCurrentRefreshRatePreferringHiDPIOn4KDisplay() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 100, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 103, width: 3008, height: 1692, pixelWidth: 6016, pixelHeight: 3384, refreshRate: 60.0),
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 201, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0),
            RawDisplayMode(modeID: 202, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 30.0),
            RawDisplayMode(modeID: 203, width: 1920, height: 1200, pixelWidth: 3840, pixelHeight: 2400, refreshRate: 60.0),
            RawDisplayMode(modeID: 204, width: 1024, height: 768, pixelWidth: 1024, pixelHeight: 768, refreshRate: 60.0),
            RawDisplayMode(modeID: 104, width: 1504, height: 846, pixelWidth: 3008, pixelHeight: 1692, refreshRate: 60.0),
            RawDisplayMode(modeID: 205, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0, isUsableForDesktopGUI: false)
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

        XCTAssertEqual(display.availableModes.map(\.modeID), [104, 101, 102, 103])
        XCTAssertTrue(display.availableModes.allSatisfy(\.isHiDPI))
        XCTAssertEqual(
            display.availableModes.map(\.label),
            ["1504x846 · 78%", "1920x1080", "2560x1440 · 133%", "3008x1692 · 157%"]
        )
        XCTAssertEqual(display.currentModeID, 102)
        XCTAssertEqual(display.resolutionLabel, "2560x1440 · 133%")
    }

    func testFormatsRetinaBuiltInAndStandard1xExternalDisplayResolutionLabels() {
        let builtInModes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 10, width: 3024, height: 1964, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120.0),
            RawDisplayMode(modeID: 13, width: 1800, height: 1169, pixelWidth: 3600, pixelHeight: 2338, refreshRate: 120.0),
            RawDisplayMode(modeID: 12, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120.0),
            RawDisplayMode(modeID: 11, width: 1352, height: 878, pixelWidth: 2704, pixelHeight: 1756, refreshRate: 120.0)
        ]
        let standard1080pModes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 23, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60.0),
            RawDisplayMode(modeID: 21, width: 1280, height: 720, pixelWidth: 1280, pixelHeight: 720, refreshRate: 60.0),
            RawDisplayMode(modeID: 22, width: 1600, height: 900, pixelWidth: 1600, pixelHeight: 900, refreshRate: 60.0),
            RawDisplayMode(modeID: 24, width: 1024, height: 768, pixelWidth: 1024, pixelHeight: 768, refreshRate: 60.0)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(
                displayID: 1,
                name: "Built-in Display",
                isBuiltIn: true,
                isMain: true,
                currentModeID: 12,
                modes: builtInModes
            ),
            RawDisplayInfo(
                displayID: 20,
                name: "DELL P2217H",
                isBuiltIn: false,
                isMain: false,
                currentModeID: 23,
                modes: standard1080pModes
            )
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.count, 2)

        let builtIn = coordinator.displays[0]
        XCTAssertEqual(
            builtIn.availableModes.map(\.label),
            ["1352x878 · 89%", "1512x982", "1800x1169 · 119%"]
        )
        XCTAssertEqual(builtIn.resolutionLabel, "1512x982")

        let dell1080p = coordinator.displays[1]
        XCTAssertEqual(
            dell1080p.availableModes.map(\.label),
            ["1280x720", "1600x900", "1920x1080"]
        )
        XCTAssertTrue(dell1080p.availableModes.allSatisfy { !$0.isHiDPI })
        XCTAssertEqual(dell1080p.resolutionLabel, "1920x1080")
    }

    func testStandard1080pPanelExposingLowResHiDPIDuplicateKeepsStandardModes() {
        // macOS lists a 960x540 HiDPI duplicate for 1080p panels when low-resolution duplicates are requested
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 23, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60.0),
            RawDisplayMode(modeID: 21, width: 1280, height: 720, pixelWidth: 1280, pixelHeight: 720, refreshRate: 60.0),
            RawDisplayMode(modeID: 25, width: 960, height: 540, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60.0),
            RawDisplayMode(modeID: 22, width: 1600, height: 900, pixelWidth: 1600, pixelHeight: 900, refreshRate: 60.0)
        ]
        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false, currentModeID: 23, modes: modes)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        XCTAssertEqual(
            coordinator.displays.first?.availableModes.map(\.label),
            ["1280x720", "1600x900", "1920x1080"]
        )
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "1920x1080")
    }

    func testHandlesZeroHzVariableRefreshRateAndPreservesNativeAspectRatioFiltering() {
        // Built-in Retina display with notch: all modes report 0Hz (LCD/ProMotion), plus 16:10 notchless modes
        let builtInZeroHzModes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 1, width: 3024, height: 1964, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 0.0),
            RawDisplayMode(modeID: 2, width: 1024, height: 665, pixelWidth: 2048, pixelHeight: 1330, refreshRate: 0.0),
            RawDisplayMode(modeID: 3, width: 1352, height: 878, pixelWidth: 2704, pixelHeight: 1756, refreshRate: 0.0),
            RawDisplayMode(modeID: 4, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 0.0),
            RawDisplayMode(modeID: 5, width: 1800, height: 1169, pixelWidth: 3600, pixelHeight: 2338, refreshRate: 0.0),
            // 16:10 notchless modes should be excluded by native aspect ratio filter
            RawDisplayMode(modeID: 6, width: 1512, height: 945, pixelWidth: 3024, pixelHeight: 1890, refreshRate: 0.0),
            RawDisplayMode(modeID: 7, width: 1800, height: 1125, pixelWidth: 3600, pixelHeight: 2250, refreshRate: 0.0)
        ]

        // External display whose current mode reports 0Hz (unspecified) while sibling modes report 60Hz
        let mixedZeroHzModes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 20, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 0.0),
            RawDisplayMode(modeID: 21, width: 1280, height: 720, pixelWidth: 1280, pixelHeight: 720, refreshRate: 60.0),
            RawDisplayMode(modeID: 22, width: 1600, height: 900, pixelWidth: 1600, pixelHeight: 900, refreshRate: 60.0),
            RawDisplayMode(modeID: 23, width: 1024, height: 768, pixelWidth: 1024, pixelHeight: 768, refreshRate: 60.0)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 1, name: "Built-in Display", isBuiltIn: true, isMain: true, currentModeID: 4, modes: builtInZeroHzModes),
            RawDisplayInfo(displayID: 20, name: "DELL P2217H", isBuiltIn: false, isMain: false, currentModeID: 20, modes: mixedZeroHzModes)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        XCTAssertEqual(
            coordinator.displays[0].availableModes.map(\.label),
            ["1024x665 · 68%", "1352x878 · 89%", "1512x982", "1800x1169 · 119%"]
        )
        XCTAssertEqual(coordinator.displays[0].resolutionLabel, "1512x982")

        XCTAssertEqual(
            coordinator.displays[1].availableModes.map(\.label),
            ["1280x720", "1600x900", "1920x1080"]
        )
        XCTAssertEqual(coordinator.displays[1].resolutionLabel, "1920x1080")
    }

    func testMatchesNTSC5994HzWith60HzWhileExcludingOtherRefreshRates() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 100, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 59.94),
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 59.94),
            RawDisplayMode(modeID: 103, width: 3008, height: 1692, pixelWidth: 6016, pixelHeight: 3384, refreshRate: 30.0),
            RawDisplayMode(modeID: 104, width: 3360, height: 1890, pixelWidth: 6720, pixelHeight: 3780, refreshRate: 120.0)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true, currentModeID: 102, modes: modes)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        XCTAssertEqual(
            coordinator.displays.first?.availableModes.map(\.modeID),
            [101, 102]
        )
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "2560x1440 · 133%")
    }

    func testResolves16By9NativePanelWhen4KDisplayAlsoAdvertises4096x2160CinemaMode() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 99, width: 4096, height: 2160, pixelWidth: 4096, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 100, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0),
            RawDisplayMode(modeID: 103, width: 3008, height: 1692, pixelWidth: 6016, pixelHeight: 3384, refreshRate: 60.0)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true, currentModeID: 102, modes: modes)
        ])

        let coordinator = DisplayCoordinator(driver: driver)

        XCTAssertEqual(
            coordinator.displays.first?.availableModes.map(\.label),
            ["1920x1080", "2560x1440 · 133%", "3008x1692 · 157%"]
        )
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "2560x1440 · 133%")
    }

    func testDraggingResolutionSliderPreviewsLabelLiveWithoutCallingDriverAndCommitsOnceOnRelease() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 100, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 104, width: 1504, height: 846, pixelWidth: 3008, pixelHeight: 1692, refreshRate: 60.0),
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0),
            RawDisplayMode(modeID: 103, width: 3008, height: 1692, pixelWidth: 6016, pixelHeight: 3384, refreshRate: 60.0)
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

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "1920x1080")
        XCTAssertTrue(driver.setModeHistory.isEmpty)

        // Drag through two stops without releasing
        coordinator.previewResolution(30, modeID: 102)
        XCTAssertEqual(coordinator.displays.first?.previewModeID, 102)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 101)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "2560x1440 · 133%")
        XCTAssertTrue(driver.setModeHistory.isEmpty)

        coordinator.previewResolution(30, stepIndex: 3)
        XCTAssertEqual(coordinator.displays.first?.previewModeID, 103)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 101)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "3008x1692 · 157%")
        XCTAssertTrue(driver.setModeHistory.isEmpty)

        // Release slider to commit once
        coordinator.commitResolution(30)
        XCTAssertEqual(driver.setModeHistory.count, 1)
        XCTAssertEqual(driver.setModeHistory.first?.displayID, 30)
        XCTAssertEqual(driver.setModeHistory.first?.modeID, 103)
        XCTAssertNil(coordinator.displays.first?.previewModeID)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 103)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "3008x1692 · 157%")
    }

    func testSelectingResolutionFromDropdownCommitsModeImmediately() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 100, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0)
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

        let coordinator = DisplayCoordinator(driver: driver)
        coordinator.commitResolution(30, modeID: 102)

        XCTAssertEqual(driver.setModeHistory.count, 1)
        XCTAssertEqual(driver.setModeHistory.first?.displayID, 30)
        XCTAssertEqual(driver.setModeHistory.first?.modeID, 102)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 102)
        XCTAssertNil(coordinator.displays.first?.previewModeID)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "2560x1440 · 133%")
    }

    func testReleasingSliderOnUnchangedResolutionClearsPreviewWithoutCallingDriver() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 100, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true, currentModeID: 101, modes: modes)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.first?.activeOrPreviewModeIndex, 0)

        coordinator.previewResolution(30, stepIndex: 1)
        XCTAssertEqual(coordinator.displays.first?.activeOrPreviewModeIndex, 1)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "2560x1440 · 133%")

        // Drag back to initial stop and release
        coordinator.previewResolution(30, stepIndex: 0)
        coordinator.commitResolution(30)

        XCTAssertTrue(driver.setModeHistory.isEmpty)
        XCTAssertNil(coordinator.displays.first?.previewModeID)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 101)
        XCTAssertEqual(coordinator.displays.first?.activeOrPreviewModeIndex, 0)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "1920x1080")
    }

    func testFailedModeCommitKeepsPreviousCurrentModeAndClearsPreview() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 100, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: true, currentModeID: 101, modes: modes)
        ])
        driver.setDisplayModeError = DisplayDriverError.configurationFailed(-1)

        let coordinator = DisplayCoordinator(driver: driver)
        coordinator.previewResolution(30, modeID: 102)
        coordinator.commitResolution(30)

        XCTAssertEqual(driver.setModeHistory.count, 1)
        XCTAssertNil(coordinator.displays.first?.previewModeID)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 101)
        XCTAssertEqual(coordinator.displays.first?.resolutionLabel, "1920x1080")
    }

    func testResolutionChangesAreIgnoredForDisabledDisplay() {
        let modes: [RawDisplayMode] = [
            RawDisplayMode(modeID: 100, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 101, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0),
            RawDisplayMode(modeID: 102, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0)
        ]

        let driver = FakeDisplayDriver(onlineDisplays: [
            RawDisplayInfo(displayID: 30, name: "DELL U2725QE", isBuiltIn: false, isMain: false, isActive: false, currentModeID: 101, modes: modes)
        ])

        let coordinator = DisplayCoordinator(driver: driver)
        XCTAssertEqual(coordinator.displays.first?.isEnabled, false)

        coordinator.previewResolution(30, modeID: 102)
        coordinator.commitResolution(30, modeID: 102)

        XCTAssertTrue(driver.setModeHistory.isEmpty)
        XCTAssertNil(coordinator.displays.first?.previewModeID)
        XCTAssertEqual(coordinator.displays.first?.currentModeID, 101)
    }
}
