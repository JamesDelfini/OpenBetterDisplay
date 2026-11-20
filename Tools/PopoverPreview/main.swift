import AppKit
import Foundation
import OpenBetterDisplayCore
import OpenBetterDisplayUI
import SwiftUI

private final class PreviewDisplayDriver: DisplayDriver, @unchecked Sendable {
    private let displays: [RawDisplayInfo]
    private let brightnessByID: [UInt32: BrightnessReading]

    init(displays: [RawDisplayInfo], brightnessByID: [UInt32: BrightnessReading]) {
        self.displays = displays
        self.brightnessByID = brightnessByID
    }

    func fetchOnlineDisplays() -> [RawDisplayInfo] {
        displays
    }

    func setDisplayEnabled(_ displayID: UInt32, enabled: Bool) throws {}
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

@MainActor
private func renderPreview() {
    let args = Array(CommandLine.arguments.dropFirst())
    var outputPath = "/tmp/openbetterdisplay-preview.png"
    var expandID: UInt32?

    var index = 0
    while index < args.count {
        let arg = args[index]
        if arg == "--expanded", index + 1 < args.count, let id = UInt32(args[index + 1]) {
            expandID = id
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
                    RawDisplayMode(modeID: 10, width: 1147, height: 745, pixelWidth: 2294, pixelHeight: 1490),
                    RawDisplayMode(modeID: 11, width: 1352, height: 878, pixelWidth: 2704, pixelHeight: 1756),
                    RawDisplayMode(modeID: 12, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, isNative: true),
                    RawDisplayMode(modeID: 13, width: 1800, height: 1169, pixelWidth: 3600, pixelHeight: 2338)
                ]
            ),
            RawDisplayInfo(
                displayID: 20,
                name: "DELL P2217H",
                isBuiltIn: false,
                isMain: false,
                currentModeID: 22,
                modes: [
                    RawDisplayMode(modeID: 20, width: 1280, height: 720, pixelWidth: 1280, pixelHeight: 720),
                    RawDisplayMode(modeID: 21, width: 1600, height: 900, pixelWidth: 1600, pixelHeight: 900),
                    RawDisplayMode(modeID: 22, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, isNative: true)
                ]
            ),
            RawDisplayInfo(
                displayID: 30,
                name: "DELL U2725QE",
                isBuiltIn: false,
                isMain: true,
                currentModeID: 32,
                modes: [
                    RawDisplayMode(modeID: 30, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160),
                    RawDisplayMode(modeID: 31, width: 2304, height: 1296, pixelWidth: 4608, pixelHeight: 2592),
                    RawDisplayMode(modeID: 32, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880),
                    RawDisplayMode(modeID: 33, width: 3008, height: 1692, pixelWidth: 6016, pixelHeight: 3384),
                    RawDisplayMode(modeID: 34, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, isNative: true)
                ]
            )
        ],
        brightnessByID: [
            1: BrightnessReading(level: 0.93, backend: .nativeAppleBacklight),
            20: BrightnessReading(level: 1.0, backend: .hardwareDDC),
            30: BrightnessReading(level: 0.60, backend: .hardwareDDC)
        ]
    )

    let coordinator = DisplayCoordinator(
        driver: driver,
        brightnessStore: PreviewBrightnessStore(),
        ddcThrottleInterval: 0
    )

    if let expandID {
        coordinator.toggleExpandedDisplay(expandID)
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
