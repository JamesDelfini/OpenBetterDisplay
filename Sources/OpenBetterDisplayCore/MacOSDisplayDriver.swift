import AppKit
import CoreGraphics
import Darwin
import Foundation

public enum DisplayDriverError: Error, LocalizedError, Equatable {
    case skyLightUnavailable
    case configurationFailed(Int32)
    case modeNotFound(Int32)

    public var errorDescription: String? {
        switch self {
        case .skyLightUnavailable:
            return "SkyLight framework symbol is unavailable."
        case .configurationFailed(let code):
            return "CoreGraphics display configuration failed with error \(code)."
        case .modeNotFound(let modeID):
            return "Display mode \(modeID) was not found."
        }
    }
}

public final class MacOSDisplayDriver: DisplayDriver, @unchecked Sendable {
    private static let displayModeNativeFlag: UInt32 = 0x0200_0000

    private typealias CGSGetDisplayListFn = @convention(c) (
        UInt32,
        UnsafeMutablePointer<CGDirectDisplayID>?,
        UnsafeMutablePointer<UInt32>?
    ) -> CGError

    private typealias CGSConfigureDisplayEnabledFn = @convention(c) (
        CGDisplayConfigRef?,
        CGDirectDisplayID,
        Bool
    ) -> CGError

    private typealias CGSConfigureDisplayModeFn = @convention(c) (
        CGDisplayConfigRef?,
        CGDirectDisplayID,
        Int32
    ) -> CGError

    private typealias CoreDisplayCreateInfoDictionaryFn = @convention(c) (
        CGDirectDisplayID
    ) -> Unmanaged<CFDictionary>?

    private typealias DisplayServicesCanChangeBrightnessFn = @convention(c) (
        CGDirectDisplayID
    ) -> Bool

    private typealias DisplayServicesGetBrightnessFn = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32

    private typealias DisplayServicesSetBrightnessFn = @convention(c) (
        CGDirectDisplayID,
        Float
    ) -> Int32

    private let skyLightHandle: UnsafeMutableRawPointer?
    private let coreDisplayHandle: UnsafeMutableRawPointer?
    private let displayServicesHandle: UnsafeMutableRawPointer?

    private let cgsGetDisplayList: CGSGetDisplayListFn?
    private let cgsConfigureDisplayEnabled: CGSConfigureDisplayEnabledFn?
    private let cgsConfigureDisplayMode: CGSConfigureDisplayModeFn?
    private let coreDisplayCreateInfoDictionary: CoreDisplayCreateInfoDictionaryFn?
    private let displayServicesCanChangeBrightness: DisplayServicesCanChangeBrightnessFn?
    private let displayServicesGetBrightness: DisplayServicesGetBrightnessFn?
    private let displayServicesSetBrightness: DisplayServicesSetBrightnessFn?

    public init() {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        self.skyLightHandle = skyLight
        if let skyLight {
            if let sym = dlsym(skyLight, "CGSGetDisplayList") {
                self.cgsGetDisplayList = unsafeBitCast(sym, to: CGSGetDisplayListFn.self)
            } else {
                self.cgsGetDisplayList = nil
            }
            if let sym = dlsym(skyLight, "CGSConfigureDisplayEnabled") {
                self.cgsConfigureDisplayEnabled = unsafeBitCast(sym, to: CGSConfigureDisplayEnabledFn.self)
            } else {
                self.cgsConfigureDisplayEnabled = nil
            }
            if let sym = dlsym(skyLight, "CGSConfigureDisplayMode") {
                self.cgsConfigureDisplayMode = unsafeBitCast(sym, to: CGSConfigureDisplayModeFn.self)
            } else {
                self.cgsConfigureDisplayMode = nil
            }
        } else {
            self.cgsGetDisplayList = nil
            self.cgsConfigureDisplayEnabled = nil
            self.cgsConfigureDisplayMode = nil
        }

        let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
        self.coreDisplayHandle = coreDisplay
        if let coreDisplay, let sym = dlsym(coreDisplay, "CoreDisplay_DisplayCreateInfoDictionary") {
            self.coreDisplayCreateInfoDictionary = unsafeBitCast(sym, to: CoreDisplayCreateInfoDictionaryFn.self)
        } else {
            self.coreDisplayCreateInfoDictionary = nil
        }

        let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        self.displayServicesHandle = displayServices
        if let displayServices {
            if let sym = dlsym(displayServices, "DisplayServicesCanChangeBrightness") {
                self.displayServicesCanChangeBrightness = unsafeBitCast(sym, to: DisplayServicesCanChangeBrightnessFn.self)
            } else {
                self.displayServicesCanChangeBrightness = nil
            }
            if let sym = dlsym(displayServices, "DisplayServicesGetBrightness") {
                self.displayServicesGetBrightness = unsafeBitCast(sym, to: DisplayServicesGetBrightnessFn.self)
            } else {
                self.displayServicesGetBrightness = nil
            }
            if let sym = dlsym(displayServices, "DisplayServicesSetBrightness") {
                self.displayServicesSetBrightness = unsafeBitCast(sym, to: DisplayServicesSetBrightnessFn.self)
            } else {
                self.displayServicesSetBrightness = nil
            }
        } else {
            self.displayServicesCanChangeBrightness = nil
            self.displayServicesGetBrightness = nil
            self.displayServicesSetBrightness = nil
        }
    }

    public func fetchOnlineDisplays() -> [RawDisplayInfo] {
        let displayIDs = collectConnectedDisplayIDs()
        return displayIDs.map { displayID in
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let isMain = CGDisplayIsMain(displayID) != 0
            let isActive = CGDisplayIsActive(displayID) != 0
            let vendorID = CGDisplayVendorNumber(displayID)
            let modelID = CGDisplayModelNumber(displayID)
            let serialNumber = CGDisplaySerialNumber(displayID)
            let name = resolveDisplayName(for: displayID, isBuiltIn: isBuiltIn, vendorID: vendorID, modelID: modelID)
            let currentModeID = CGDisplayCopyDisplayMode(displayID)?.ioDisplayModeID ?? 0
            let modes = fetchDisplayModes(for: displayID)

            return RawDisplayInfo(
                displayID: displayID,
                name: name,
                isBuiltIn: isBuiltIn,
                isMain: isMain,
                isActive: isActive,
                vendorID: vendorID,
                modelID: modelID,
                serialNumber: serialNumber,
                currentModeID: currentModeID,
                modes: modes
            )
        }
    }

    public func setDisplayEnabled(_ displayID: UInt32, enabled: Bool) throws {
        guard let cgsConfigureDisplayEnabled else {
            throw DisplayDriverError.skyLightUnavailable
        }
        var configRef: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&configRef)
        guard beginErr == .success, let configRef else {
            throw DisplayDriverError.configurationFailed(beginErr.rawValue)
        }
        let configureErr = cgsConfigureDisplayEnabled(configRef, displayID, enabled)
        guard configureErr == .success else {
            CGCancelDisplayConfiguration(configRef)
            throw DisplayDriverError.configurationFailed(configureErr.rawValue)
        }
        let completeErr = CGCompleteDisplayConfiguration(configRef, .forSession)
        guard completeErr == .success else {
            throw DisplayDriverError.configurationFailed(completeErr.rawValue)
        }
    }

    public func setMainDisplay(_ displayID: UInt32) throws {
        guard CGDisplayIsActive(displayID) != 0 else {
            throw DisplayDriverError.configurationFailed(CGError.illegalArgument.rawValue)
        }

        let targetBounds = CGDisplayBounds(displayID)
        let offsetX = -Int32(targetBounds.origin.x.rounded())
        let offsetY = -Int32(targetBounds.origin.y.rounded())

        var activeIDs = collectConnectedDisplayIDs().filter { CGDisplayIsActive($0) != 0 }
        if !activeIDs.contains(displayID) {
            activeIDs.append(displayID)
        }

        var configRef: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&configRef)
        guard beginErr == .success, let configRef else {
            throw DisplayDriverError.configurationFailed(beginErr.rawValue)
        }

        let targetErr = CGConfigureDisplayOrigin(configRef, displayID, 0, 0)
        guard targetErr == .success else {
            CGCancelDisplayConfiguration(configRef)
            throw DisplayDriverError.configurationFailed(targetErr.rawValue)
        }

        for id in activeIDs where id != displayID {
            // Skip displays that mirror another display; their origin follows their primary.
            if CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay {
                continue
            }
            let bounds = CGDisplayBounds(id)
            let newX = Int32(bounds.origin.x.rounded()) + offsetX
            let newY = Int32(bounds.origin.y.rounded()) + offsetY
            let originErr = CGConfigureDisplayOrigin(configRef, id, newX, newY)
            guard originErr == .success else {
                CGCancelDisplayConfiguration(configRef)
                throw DisplayDriverError.configurationFailed(originErr.rawValue)
            }
        }

        let completeErr = CGCompleteDisplayConfiguration(configRef, .forSession)
        guard completeErr == .success else {
            throw DisplayDriverError.configurationFailed(completeErr.rawValue)
        }
    }

    public func getBrightness(_ displayID: UInt32) -> BrightnessReading {
        if let displayServicesGetBrightness {
            var value: Float = 1.0
            let status = displayServicesGetBrightness(displayID, &value)
            if status == 0 {
                return BrightnessReading(
                    level: Double(max(0.0, min(1.0, value))),
                    backend: .nativeAppleBacklight
                )
            }
        }
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        return BrightnessReading(
            level: 1.0,
            backend: isBuiltIn ? .nativeAppleBacklight : .softwareGamma
        )
    }

    public func setBrightness(_ displayID: UInt32, level: Double) -> BrightnessBackendUsed {
        let clamped = max(0.0, min(1.0, level))
        if let displayServicesSetBrightness {
            let canChange = displayServicesCanChangeBrightness?(displayID) ?? (CGDisplayIsBuiltin(displayID) != 0)
            if canChange, displayServicesSetBrightness(displayID, Float(clamped)) == 0 {
                return .nativeAppleBacklight
            }
        }
        applySoftwareGamma(displayID: displayID, level: clamped)
        return .softwareGamma
    }

    public func setDisplayMode(_ displayID: UInt32, modeID: Int32) throws {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
        let targetMode = modes.first(where: { $0.ioDisplayModeID == modeID })

        guard targetMode != nil || cgsConfigureDisplayMode != nil else {
            throw DisplayDriverError.modeNotFound(modeID)
        }

        var configRef: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&configRef)
        guard beginErr == .success, let configRef else {
            throw DisplayDriverError.configurationFailed(beginErr.rawValue)
        }

        var configErr: CGError = .failure
        if let targetMode {
            configErr = CGConfigureDisplayWithDisplayMode(configRef, displayID, targetMode, nil)
        }
        if configErr != .success, let cgsConfigureDisplayMode {
            configErr = cgsConfigureDisplayMode(configRef, displayID, modeID)
        }

        guard configErr == .success else {
            CGCancelDisplayConfiguration(configRef)
            if targetMode == nil {
                throw DisplayDriverError.modeNotFound(modeID)
            }
            throw DisplayDriverError.configurationFailed(configErr.rawValue)
        }

        let completeErr = CGCompleteDisplayConfiguration(configRef, .forSession)
        guard completeErr == .success else {
            throw DisplayDriverError.configurationFailed(completeErr.rawValue)
        }
    }

    public func resetSoftwareGamma() {
        CGDisplayRestoreColorSyncSettings()
    }

    // MARK: - Private Helpers

    private func collectConnectedDisplayIDs() -> [CGDirectDisplayID] {
        let maxDisplays: UInt32 = 32
        var onlineIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var onlineCount: UInt32 = 0

        var seen = Set<CGDirectDisplayID>()
        var ordered: [CGDirectDisplayID] = []

        if CGGetOnlineDisplayList(maxDisplays, &onlineIDs, &onlineCount) == .success {
            for i in 0..<Int(onlineCount) {
                let id = onlineIDs[i]
                if id != 0, seen.insert(id).inserted {
                    ordered.append(id)
                }
            }
        }

        if let cgsGetDisplayList {
            var cgsIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
            var cgsCount: UInt32 = 0
            if cgsGetDisplayList(maxDisplays, &cgsIDs, &cgsCount) == .success {
                for i in 0..<Int(cgsCount) {
                    let id = cgsIDs[i]
                    if id != 0, seen.insert(id).inserted {
                        ordered.append(id)
                    }
                }
            }
        }

        return ordered
    }

    private func resolveDisplayName(
        for displayID: CGDirectDisplayID,
        isBuiltIn: Bool,
        vendorID: UInt32,
        modelID: UInt32
    ) -> String {
        if isBuiltIn {
            return "Built-in Display"
        }

        if let coreDisplayCreateInfoDictionary,
           let unmanagedDict = coreDisplayCreateInfoDictionary(displayID) {
            let cfDict = unmanagedDict.takeRetainedValue()
            if let dict = cfDict as? [String: Any],
               let productNames = dict["DisplayProductName"] as? [String: String] {
                if let enUS = productNames["en_US"], !enUS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return enUS.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let firstName = productNames.values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    return firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[screenNumberKey] as? NSNumber,
               number.uint32Value == displayID {
                let localized = screen.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !localized.isEmpty {
                    return localized
                }
            }
        }

        if vendorID != 0 || modelID != 0 {
            return String(format: "External Display (%04X:%04X)", vendorID, modelID)
        }
        return "External Display"
    }

    private func fetchDisplayModes(for displayID: CGDirectDisplayID) -> [RawDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        var cgModes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
        if let currentMode = CGDisplayCopyDisplayMode(displayID),
           !cgModes.contains(where: { $0.ioDisplayModeID == currentMode.ioDisplayModeID }) {
            cgModes.append(currentMode)
        }
        return cgModes.map { mode in
            RawDisplayMode(
                modeID: mode.ioDisplayModeID,
                width: mode.width,
                height: mode.height,
                pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate,
                isUsableForDesktopGUI: mode.isUsableForDesktopGUI(),
                isNative: (mode.ioFlags & Self.displayModeNativeFlag) != 0
            )
        }
    }

    private func applySoftwareGamma(displayID: CGDirectDisplayID, level: Double) {
        let scale = Float(max(0.08, min(1.0, level)))
        var table = (0..<256).map { index -> CGGammaValue in
            (Float(index) / 255.0) * scale
        }
        _ = CGSetDisplayTransferByTable(displayID, 256, &table, &table, &table)
    }
}

@MainActor
public final class DisplayReconfigurationObserver {
    private let onReconfigure: @MainActor () -> Void
    private nonisolated(unsafe) var notificationObserver: NSObjectProtocol?
    private nonisolated(unsafe) var isRegisteredCallback = false

    public init(onReconfigure: @escaping @MainActor () -> Void) {
        self.onReconfigure = onReconfigure
        start()
    }

    deinit {
        stop()
    }

    public func start() {
        guard !isRegisteredCallback else { return }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(Self.reconfigurationCallback, pointer)
        isRegisteredCallback = true

        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onReconfigure()
            }
        }
    }

    nonisolated public func stop() {
        if isRegisteredCallback {
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            CGDisplayRemoveReconfigurationCallback(Self.reconfigurationCallback, pointer)
            isRegisteredCallback = false
        }
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
            self.notificationObserver = nil
        }
    }

    nonisolated private static let reconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
        let observer = Unmanaged<DisplayReconfigurationObserver>.fromOpaque(userInfo).takeUnretainedValue()
        Task { @MainActor in
            observer.onReconfigure()
        }
    }
}
