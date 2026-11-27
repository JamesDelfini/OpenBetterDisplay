import AppKit
import CoreGraphics
import Foundation
import OpenBetterDisplayCore
import OpenBetterDisplayUI
import SwiftUI

private final class PreviewDisplayDriver: DisplayDriver, @unchecked Sendable {
    private var displays: [RawDisplayInfo]
    private var disconnectedDisplays: [UInt32: RawDisplayInfo] = [:]
    private let brightnessByID: [UInt32: BrightnessReading]

    init(displays: [RawDisplayInfo], brightnessByID: [UInt32: BrightnessReading]) {
        self.displays = displays
        self.brightnessByID = brightnessByID
    }

    func fetchOnlineDisplays() -> [RawDisplayInfo] {
        displays
    }

    func setDisplayEnabled(_ displayID: UInt32, enabled: Bool) throws {
        if enabled {
            if var restored = disconnectedDisplays.removeValue(forKey: displayID) {
                restored.isActive = true
                displays.append(restored)
            }
        } else if let index = displays.firstIndex(where: { $0.displayID == displayID }) {
            var removed = displays.remove(at: index)
            removed.isActive = false
            removed.isMain = false
            disconnectedDisplays[displayID] = removed
        }
    }

    func setMainDisplay(_ displayID: UInt32) throws {}

    func getBrightness(_ displayID: UInt32) -> BrightnessReading {
        brightnessByID[displayID] ?? BrightnessReading(level: 1.0, backend: .hardwareDDC)
    }

    func setBrightness(_ displayID: UInt32, level: Double) -> BrightnessBackendUsed {
        getBrightness(displayID).backend
    }

    func setDisplayMode(_ displayID: UInt32, modeID: Int32) throws {}
    func resetSoftwareGamma() {}
}

private final class PreviewBrightnessStore: BrightnessPersistence, @unchecked Sendable {
    func brightness(forKey key: String) -> Double? { nil }
    func setBrightness(_ level: Double, forKey key: String) {}
}

private final class PreviewHotkeyPreferencesStore: HotkeyPreferencesPersistence, @unchecked Sendable {
    func loadPreferences() -> HotkeyPreferences? { nil }
    func savePreferences(_ preferences: HotkeyPreferences) {}
}

@MainActor
private final class PreviewBrightnessHotkeyGateway: BrightnessHotkeyGateway {
    var onBrightnessKeyEvent: (@MainActor (BrightnessKeyEvent) -> Bool)?
    var onCheckerStatusDidChange: (@MainActor () -> Void)?
    private let checkerStatus: KeyboardCheckerStatus

    init(checkerStatus: KeyboardCheckerStatus) {
        self.checkerStatus = checkerStatus
    }

    func applyPreferences(_ preferences: HotkeyPreferences) {}
    func readCheckerStatus() -> KeyboardCheckerStatus { checkerStatus }
    func currentPointerLocation() -> CGPoint? { nil }
    func requestAccessibilityPermission() {}
    func openKeyboardSettings() {}
    func stop() {}
}

private final class PreviewFavoriteModesStore: FavoriteModesPersistence, @unchecked Sendable {
    private var slotsByKey: [String: [Int: FavoriteModeRecord]] = [:]

    func favoriteModes(forKey key: String) -> [Int: FavoriteModeRecord] {
        slotsByKey[key] ?? [:]
    }

    func setFavoriteModes(_ slots: [Int: FavoriteModeRecord], forKey key: String) {
        slotsByKey[key] = slots
    }
}

@MainActor
private func renderPreview() {
    let args = Array(CommandLine.arguments.dropFirst())
    var outputPath = "/tmp/openbetterdisplay-preview.png"
    var expandMainID: UInt32?
    var expandModeID: UInt32?
    var expandHotkeys = false
    var expandRefreshID: UInt32?
    var expandManageID: UInt32?
    var disconnectID: UInt32?

    var index = 0
    while index < args.count {
        let arg = args[index]
        if arg == "--expanded", index + 1 < args.count, let id = UInt32(args[index + 1]) {
            expandMainID = id
            index += 2
        } else if arg == "--expanded-mode", index + 1 < args.count, let id = UInt32(args[index + 1]) {
            expandModeID = id
            index += 2
        } else if arg == "--expanded-hotkeys" {
            expandHotkeys = true
            index += 1
        } else if arg == "--expanded-refresh", index + 1 < args.count, let id = UInt32(args[index + 1]) {
            expandRefreshID = id
            index += 2
        } else if arg == "--expanded-manage" {
            if index + 1 < args.count, let id = UInt32(args[index + 1]) {
                expandManageID = id
                index += 2
            } else {
                expandManageID = 30
                index += 1
            }
        } else if arg == "--disconnect", index + 1 < args.count, let id = UInt32(args[index + 1]) {
            disconnectID = id
            index += 2
        } else if !arg.hasPrefix("--") {
            outputPath = arg
            index += 1
        } else {
            index += 1
        }
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    let driver = PreviewDisplayDriver(
        displays: [
            RawDisplayInfo(
                displayID: 1,
                name: "Built-in Display",
                isBuiltIn: true,
                isMain: false,
                currentModeID: 12,
                modes: [
                    RawDisplayMode(
                        modeID: 10, width: 1147, height: 745, pixelWidth: 2294, pixelHeight: 1490, refreshRate: 120.0, bitsPerSample: 10),
                    RawDisplayMode(
                        modeID: 11, width: 1352, height: 878, pixelWidth: 2704, pixelHeight: 1756, refreshRate: 120.0, bitsPerSample: 10),
                    RawDisplayMode(
                        modeID: 12,
                        width: 1512,
                        height: 982,
                        pixelWidth: 3024,
                        pixelHeight: 1964,
                        refreshRate: 120.0,
                        isNative: true,
                        bitsPerSample: 10,
                        isDefault: true,
                        isVRR: true,
                        isProMotion: true,
                        minRefreshRate: 24.0
                    ),
                    RawDisplayMode(
                        modeID: 15,
                        width: 1512,
                        height: 982,
                        pixelWidth: 3024,
                        pixelHeight: 1964,
                        refreshRate: 60.0,
                        bitsPerSample: 10
                    ),
                    RawDisplayMode(
                        modeID: 16,
                        width: 1512,
                        height: 982,
                        pixelWidth: 3024,
                        pixelHeight: 1964,
                        refreshRate: 59.94,
                        bitsPerSample: 10
                    ),
                    RawDisplayMode(
                        modeID: 17,
                        width: 1512,
                        height: 982,
                        pixelWidth: 3024,
                        pixelHeight: 1964,
                        refreshRate: 47.95,
                        bitsPerSample: 10
                    ),
                    RawDisplayMode(
                        modeID: 13, width: 1800, height: 1169, pixelWidth: 3600, pixelHeight: 2338, refreshRate: 120.0, bitsPerSample: 10),
                    RawDisplayMode(
                        modeID: 14, width: 3024, height: 1964, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120.0, isNative: true,
                        bitsPerSample: 10)
                ],
                bounds: CGRect(x: -1512, y: 0, width: 1512, height: 982)
            ),
            RawDisplayInfo(
                displayID: 20,
                name: "DELL P2217H",
                isBuiltIn: false,
                isMain: false,
                currentModeID: 22,
                modes: [
                    RawDisplayMode(
                        modeID: 20, width: 1280, height: 720, pixelWidth: 1280, pixelHeight: 720, refreshRate: 60.0, bitsPerSample: 8),
                    RawDisplayMode(
                        modeID: 21, width: 1600, height: 900, pixelWidth: 1600, pixelHeight: 900, refreshRate: 60.0, bitsPerSample: 8),
                    RawDisplayMode(
                        modeID: 23, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 75.0, isNative: true,
                        bitsPerSample: 8),
                    RawDisplayMode(
                        modeID: 22,
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
                        modeID: 24, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 50.0, isNative: true,
                        bitsPerSample: 8)
                ],
                bounds: CGRect(x: 2560, y: 0, width: 1920, height: 1080)
            ),
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                currentModeID: 33,
                modes: [
                    RawDisplayMode(
                        modeID: 30, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 120.0, isNative: true,
                        bitsPerSample: 10, isDefault: true),
                    RawDisplayMode(
                        modeID: 31, width: 2048, height: 1152, pixelWidth: 4096, pixelHeight: 2304, refreshRate: 120.0, bitsPerSample: 10),
                    RawDisplayMode(
                        modeID: 32, width: 2304, height: 1296, pixelWidth: 4608, pixelHeight: 2592, refreshRate: 120.0, bitsPerSample: 10),
                    RawDisplayMode(
                        modeID: 33, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 120.0, bitsPerSample: 10),
                    RawDisplayMode(
                        modeID: 41,
                        width: 2560,
                        height: 1440,
                        pixelWidth: 5120,
                        pixelHeight: 2880,
                        refreshRate: 120.0,
                        bitsPerSample: 10,
                        isVRR: true,
                        minRefreshRate: 48.0
                    ),
                    RawDisplayMode(
                        modeID: 42,
                        width: 2560,
                        height: 1440,
                        pixelWidth: 5120,
                        pixelHeight: 2880,
                        refreshRate: 75.0,
                        bitsPerSample: 10,
                        isVRR: true,
                        minRefreshRate: 48.0
                    ),
                    RawDisplayMode(
                        modeID: 43, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60.0, bitsPerSample: 10),
                    RawDisplayMode(
                        modeID: 34, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60.0, bitsPerSample: 8),
                    RawDisplayMode(
                        modeID: 35, width: 3008, height: 1692, pixelWidth: 6016, pixelHeight: 3384, refreshRate: 120.0, bitsPerSample: 10),
                    RawDisplayMode(
                        modeID: 36, width: 3200, height: 1800, pixelWidth: 6400, pixelHeight: 3600, refreshRate: 120.0, bitsPerSample: 10),
                    RawDisplayMode(
                        modeID: 37, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 120.0, isNative: true,
                        bitsPerSample: 10),
                    RawDisplayMode(
                        modeID: 38, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60.0, isNative: true,
                        bitsPerSample: 8),
                    RawDisplayMode(
                        modeID: 39, width: 1280, height: 720, pixelWidth: 1280, pixelHeight: 720, refreshRate: 60.0, bitsPerSample: 8),
                    RawDisplayMode(
                        modeID: 40, width: 960, height: 540, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60.0, bitsPerSample: 8)
                ],
                bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440)
            )
        ],
        brightnessByID: [
            1: BrightnessReading(level: 0.93, backend: .nativeAppleBacklight),
            20: BrightnessReading(level: 1.0, backend: .hardwareDDC),
            30: BrightnessReading(level: 0.60, backend: .hardwareDDC)
        ]
    )

    let favoriteStore = PreviewFavoriteModesStore()
    let hotkeyGateway = PreviewBrightnessHotkeyGateway(
        checkerStatus: KeyboardCheckerStatus(
            functionKeyMode: .standardFunctionKeys,
            isAccessibilityTrusted: false
        )
    )
    let coordinator = DisplayCoordinator(
        driver: driver,
        brightnessStore: PreviewBrightnessStore(),
        favoriteModesStore: favoriteStore,
        ddcThrottleInterval: 0,
        hotkeyGateway: hotkeyGateway,
        hotkeyPreferencesStore: PreviewHotkeyPreferencesStore()
    )

    if let disconnectID {
        coordinator.setDisplayEnabled(disconnectID, enabled: false)
    }

    if expandHotkeys {
        coordinator.toggleExpandedSection(.hotkeys)
    } else if let expandManageID {
        if let display = coordinator.displays.first(where: { $0.displayID == expandManageID }) {
            coordinator.assignCurrentModeToFavorite(expandManageID, slot: 1)
            if let alternate = display.availableModes.first(where: { $0.modeID != display.currentModeID }) {
                coordinator.assignFavoriteMode(expandManageID, modeID: alternate.modeID, slot: 3)
            }
        }
        coordinator.toggleManageFavorites(for: expandManageID)
    } else if let expandModeID {
        coordinator.toggleExpandedSection(.displayMode(expandModeID))
    } else if let expandRefreshID {
        coordinator.toggleExpandedSection(.refreshRate(expandRefreshID))
    } else if let expandMainID {
        coordinator.toggleExpandedSection(.mainDisplay(expandMainID))
    }

    let previewSurface = DisplayPopoverView(coordinator: coordinator)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.13, green: 0.14, blue: 0.17))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(16)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))

    let hostingView = NSHostingView(rootView: previewSurface)
    hostingView.appearance = NSAppearance(named: .vibrantDark)
    let fittingSize = hostingView.fittingSize
    hostingView.frame = NSRect(origin: .zero, size: fittingSize)
    hostingView.layoutSubtreeIfNeeded()

    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: fittingSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.appearance = NSAppearance(named: .vibrantDark)
    window.contentView = hostingView
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        fputs("error: unable to create bitmap representation\n", stderr)
        exit(1)
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fputs("error: unable to encode PNG\n", stderr)
        exit(1)
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Rendered popover preview (\(Int(fittingSize.width))x\(Int(fittingSize.height))) to \(outputPath)")
    } catch {
        fputs("error: failed to write preview: \(error)\n", stderr)
        exit(1)
    }
}

MainActor.assumeIsolated {
    renderPreview()
}
