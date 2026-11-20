import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit

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

    private typealias IOAVServiceCreateWithServiceFn = @convention(c) (
        CFAllocator?,
        io_service_t
    ) -> Unmanaged<CFTypeRef>?

    private typealias IOAVServiceReadI2CFn = @convention(c) (
        CFTypeRef,
        UInt32,
        UInt32,
        UnsafeMutableRawPointer,
        UInt32
    ) -> IOReturn

    private typealias IOAVServiceWriteI2CFn = @convention(c) (
        CFTypeRef,
        UInt32,
        UInt32,
        UnsafeRawPointer,
        UInt32
    ) -> IOReturn

    private typealias IOAVServiceCopyEDIDFn = @convention(c) (
        CFTypeRef,
        UnsafeMutablePointer<Unmanaged<CFData>?>
    ) -> IOReturn

    private typealias IOAVServiceGetLocationFn = @convention(c) (
        CFTypeRef
    ) -> UInt32

    private enum DDCCacheEntry {
        case supported(service: CFTypeRef, registryPath: String, maxValue: Int)
        case unsupported
    }

    private let skyLightHandle: UnsafeMutableRawPointer?
    private let coreDisplayHandle: UnsafeMutableRawPointer?
    private let displayServicesHandle: UnsafeMutableRawPointer?
    private let ioKitHandle: UnsafeMutableRawPointer?

    private let cgsGetDisplayList: CGSGetDisplayListFn?
    private let cgsConfigureDisplayEnabled: CGSConfigureDisplayEnabledFn?
    private let cgsConfigureDisplayMode: CGSConfigureDisplayModeFn?
    private let coreDisplayCreateInfoDictionary: CoreDisplayCreateInfoDictionaryFn?
    private let displayServicesCanChangeBrightness: DisplayServicesCanChangeBrightnessFn?
    private let displayServicesGetBrightness: DisplayServicesGetBrightnessFn?
    private let displayServicesSetBrightness: DisplayServicesSetBrightnessFn?
    private let ioAVServiceCreateWithService: IOAVServiceCreateWithServiceFn?
    private let ioAVServiceReadI2C: IOAVServiceReadI2CFn?
    private let ioAVServiceWriteI2C: IOAVServiceWriteI2CFn?
    private let ioAVServiceCopyEDID: IOAVServiceCopyEDIDFn?
    private let ioAVServiceGetLocation: IOAVServiceGetLocationFn?

    private let ddcLock = NSLock()
    private var ddcCache: [CGDirectDisplayID: DDCCacheEntry] = [:]
    private var softwareGammaLevels: [CGDirectDisplayID: Double] = [:]

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

        let ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        self.ioKitHandle = ioKit
        if let ioKit {
            if let sym = dlsym(ioKit, "IOAVServiceCreateWithService") {
                self.ioAVServiceCreateWithService = unsafeBitCast(sym, to: IOAVServiceCreateWithServiceFn.self)
            } else {
                self.ioAVServiceCreateWithService = nil
            }
            if let sym = dlsym(ioKit, "IOAVServiceReadI2C") {
                self.ioAVServiceReadI2C = unsafeBitCast(sym, to: IOAVServiceReadI2CFn.self)
            } else {
                self.ioAVServiceReadI2C = nil
            }
            if let sym = dlsym(ioKit, "IOAVServiceWriteI2C") {
                self.ioAVServiceWriteI2C = unsafeBitCast(sym, to: IOAVServiceWriteI2CFn.self)
            } else {
                self.ioAVServiceWriteI2C = nil
            }
            if let sym = dlsym(ioKit, "IOAVServiceCopyEDID") {
                self.ioAVServiceCopyEDID = unsafeBitCast(sym, to: IOAVServiceCopyEDIDFn.self)
            } else {
                self.ioAVServiceCopyEDID = nil
            }
            if let sym = dlsym(ioKit, "IOAVServiceGetLocation") {
                self.ioAVServiceGetLocation = unsafeBitCast(sym, to: IOAVServiceGetLocationFn.self)
            } else {
                self.ioAVServiceGetLocation = nil
            }
        } else {
            self.ioAVServiceCreateWithService = nil
            self.ioAVServiceReadI2C = nil
            self.ioAVServiceWriteI2C = nil
            self.ioAVServiceCopyEDID = nil
            self.ioAVServiceGetLocation = nil
        }
    }

    public func fetchOnlineDisplays() -> [RawDisplayInfo] {
        let displayIDs = collectConnectedDisplayIDs()
        let activeIDSet = Set(displayIDs)
        ddcLock.lock()
        ddcCache = ddcCache.filter { activeIDSet.contains($0.key) }
        softwareGammaLevels = softwareGammaLevels.filter { activeIDSet.contains($0.key) }
        ddcLock.unlock()

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
        ddcLock.lock()
        ddcCache.removeValue(forKey: displayID)
        softwareGammaLevels.removeValue(forKey: displayID)
        ddcLock.unlock()
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
        if let nativeLevel = readNativeAppleBacklight(displayID) {
            return BrightnessReading(level: nativeLevel, backend: .nativeAppleBacklight)
        }

        if CGDisplayIsBuiltin(displayID) != 0 {
            ddcLock.lock()
            let level = softwareGammaLevels[displayID] ?? 1.0
            ddcLock.unlock()
            return BrightnessReading(level: level, backend: .nativeAppleBacklight)
        }

        ddcLock.lock()
        defer { ddcLock.unlock() }

        if let reply = readDDCBrightnessWithCacheLocked(for: displayID) {
            return BrightnessReading(level: reply.normalizedLevel, backend: .hardwareDDC)
        }

        let fallbackLevel = softwareGammaLevels[displayID] ?? 1.0
        return BrightnessReading(level: fallbackLevel, backend: .softwareGamma)
    }

    public func setBrightness(_ displayID: UInt32, level: Double) -> BrightnessBackendUsed {
        let clamped = max(0.0, min(1.0, level))

        if writeNativeAppleBacklight(displayID, level: clamped) {
            ddcLock.lock()
            clearSoftwareGammaIfAppliedLocked(displayID: displayID)
            ddcLock.unlock()
            return .nativeAppleBacklight
        }

        ddcLock.lock()
        defer { ddcLock.unlock() }

        if CGDisplayIsBuiltin(displayID) == 0,
           writeDDCBrightnessWithCacheLocked(for: displayID, level: clamped) {
            clearSoftwareGammaIfAppliedLocked(displayID: displayID)
            return .hardwareDDC
        }

        applySoftwareGammaLocked(displayID: displayID, level: clamped)
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
        ddcLock.lock()
        softwareGammaLevels.removeAll()
        ddcLock.unlock()
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

    // MARK: - Tier 1 (DisplayServices), Tier 2 (Apple Silicon DDC/CI), Tier 3 (Software Gamma)

    private func supportsNativeAppleBacklight(_ displayID: CGDirectDisplayID) -> Bool {
        if let displayServicesCanChangeBrightness {
            return displayServicesCanChangeBrightness(displayID)
        }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    private func readNativeAppleBacklight(_ displayID: CGDirectDisplayID) -> Double? {
        guard supportsNativeAppleBacklight(displayID),
              let displayServicesGetBrightness else {
            return nil
        }
        var value: Float = 1.0
        guard displayServicesGetBrightness(displayID, &value) == 0 else {
            return nil
        }
        return Double(max(0.0, min(1.0, value)))
    }

    private func writeNativeAppleBacklight(_ displayID: CGDirectDisplayID, level: Double) -> Bool {
        guard supportsNativeAppleBacklight(displayID),
              let displayServicesSetBrightness else {
            return false
        }
        return displayServicesSetBrightness(displayID, Float(level)) == 0
    }

    private func readDDCBrightnessWithCacheLocked(for displayID: CGDirectDisplayID) -> DDCProtocol.LuminanceReply? {
        if let cached = ddcCache[displayID] {
            switch cached {
            case .unsupported:
                return nil
            case .supported(let service, let path, _):
                if let reply = readDDCLuminanceLocked(avService: service) {
                    ddcCache[displayID] = .supported(
                        service: service,
                        registryPath: path,
                        maxValue: reply.maxValue
                    )
                    return reply
                }
                ddcCache.removeValue(forKey: displayID)
            }
        }

        if let resolved = resolveDDCServiceLocked(for: displayID),
           let reply = readDDCLuminanceLocked(avService: resolved.service) {
            ddcCache[displayID] = .supported(
                service: resolved.service,
                registryPath: resolved.registryPath,
                maxValue: reply.maxValue
            )
            return reply
        }

        ddcCache[displayID] = .unsupported
        return nil
    }

    private func writeDDCBrightnessWithCacheLocked(for displayID: CGDirectDisplayID, level: Double) -> Bool {
        if let cached = ddcCache[displayID] {
            switch cached {
            case .unsupported:
                return false
            case .supported(let service, _, let maxValue):
                if writeDDCLuminanceLocked(avService: service, level: level, maxValue: maxValue) {
                    return true
                }
                ddcCache.removeValue(forKey: displayID)
            }
        }

        if let resolved = resolveDDCServiceLocked(for: displayID),
           let reply = readDDCLuminanceLocked(avService: resolved.service) {
            let maxValue = reply.maxValue
            if writeDDCLuminanceLocked(avService: resolved.service, level: level, maxValue: maxValue) {
                ddcCache[displayID] = .supported(
                    service: resolved.service,
                    registryPath: resolved.registryPath,
                    maxValue: maxValue
                )
                return true
            }
        }

        ddcCache[displayID] = .unsupported
        return false
    }

    private func resolveDDCServiceLocked(
        for displayID: CGDirectDisplayID
    ) -> (service: CFTypeRef, registryPath: String)? {
        guard CGDisplayIsBuiltin(displayID) == 0,
              let ioAVServiceCreateWithService else {
            return nil
        }

        let target = buildDisplayMatchTarget(for: displayID)

        var iterator: io_iterator_t = 0
        let matchResult = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("DCPAVServiceProxy"),
            &iterator
        )
        guard matchResult == kIOReturnSuccess, iterator != 0 else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var candidates: [(service: CFTypeRef, candidate: DDCProtocol.DDCServiceCandidate)] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            if let location = readStringProperty("Location", from: service),
               location == "Embedded" {
                continue
            }

            guard let unmanagedAVService = ioAVServiceCreateWithService(kCFAllocatorDefault, service) else {
                continue
            }
            let avService = unmanagedAVService.takeRetainedValue()

            if let ioAVServiceGetLocation, ioAVServiceGetLocation(avService) == 1 {
                continue
            }

            let registryPath = readRegistryPath(for: service)
            var parsedEDID: DDCProtocol.ParsedEDID?
            if let ioAVServiceCopyEDID {
                var unmanagedEDID: Unmanaged<CFData>?
                if ioAVServiceCopyEDID(avService, &unmanagedEDID) == kIOReturnSuccess,
                   let edidData = unmanagedEDID?.takeRetainedValue() as Data? {
                    parsedEDID = DDCProtocol.parseEDID(edidData)
                }
            }

            let candidate = DDCProtocol.DDCServiceCandidate(
                registryPath: registryPath,
                edid: parsedEDID
            )
            candidates.append((service: avService, candidate: candidate))
        }

        guard !candidates.isEmpty else { return nil }

        let claimedPaths: Set<String> = Set(ddcCache.compactMap { entryDisplayID, entry in
            guard entryDisplayID != displayID else { return nil }
            if case .supported(_, let path, _) = entry {
                return path
            }
            return nil
        })

        let scored = candidates.compactMap { item -> (service: CFTypeRef, path: String, score: Int, isClaimed: Bool)? in
            guard let score = DDCProtocol.matchScore(target: target, candidate: item.candidate) else {
                return nil
            }
            return (
                service: item.service,
                path: item.candidate.registryPath,
                score: score,
                isClaimed: claimedPaths.contains(item.candidate.registryPath)
            )
        }

        if let best = scored.max(by: { lhs, rhs in
            if lhs.isClaimed != rhs.isClaimed {
                return lhs.isClaimed && !rhs.isClaimed
            }
            return lhs.score < rhs.score
        }) {
            return (service: best.service, registryPath: best.path)
        }

        let externalDisplayCount = collectConnectedDisplayIDs().filter { CGDisplayIsBuiltin($0) == 0 }.count
        let unclaimedCandidates = candidates.filter { !claimedPaths.contains($0.candidate.registryPath) }
        if externalDisplayCount == 1, unclaimedCandidates.count == 1, let only = unclaimedCandidates.first {
            return (service: only.service, registryPath: only.candidate.registryPath)
        }

        return nil
    }

    private func buildDisplayMatchTarget(for displayID: CGDirectDisplayID) -> DDCProtocol.DisplayMatchTarget {
        let vendorID = CGDisplayVendorNumber(displayID)
        let modelID = CGDisplayModelNumber(displayID)
        let serialNumber = CGDisplaySerialNumber(displayID)

        var productName: String?
        var weekOfManufacture: Int?
        var yearOfManufacture: Int?
        var ioDisplayLocation: String?
        var alphanumericSerial: String?

        if let coreDisplayCreateInfoDictionary,
           let unmanagedDict = coreDisplayCreateInfoDictionary(displayID) {
            let cfDict = unmanagedDict.takeRetainedValue()
            if let dict = cfDict as? [String: Any] {
                if let productNames = dict["DisplayProductName"] as? [String: String] {
                    if let enUS = productNames["en_US"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !enUS.isEmpty {
                        productName = enUS
                    } else if let first = productNames.values.first(where: {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }) {
                        productName = first.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                weekOfManufacture = (dict["DisplayWeekManufacture"] as? NSNumber)?.intValue
                yearOfManufacture = (dict["DisplayYearManufacture"] as? NSNumber)?.intValue
                ioDisplayLocation = dict["IODisplayLocation"] as? String
            }
        }

        if let ioDisplayLocation {
            let entry = IORegistryEntryFromPath(kIOMainPortDefault, ioDisplayLocation)
            if entry != 0 {
                defer { IOObjectRelease(entry) }
                if let attributes = IORegistryEntryCreateCFProperty(
                    entry,
                    "DisplayAttributes" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? [String: Any],
                   let productAttributes = attributes["ProductAttributes"] as? [String: Any],
                   let alphaSerial = productAttributes["AlphanumericSerialNumber"] as? String {
                    alphanumericSerial = alphaSerial
                }
            }
        }

        return DDCProtocol.DisplayMatchTarget(
            vendorID: vendorID,
            modelID: modelID,
            serialNumber: serialNumber,
            productName: productName,
            alphanumericSerial: alphanumericSerial,
            weekOfManufacture: weekOfManufacture,
            yearOfManufacture: yearOfManufacture,
            ioDisplayLocation: ioDisplayLocation
        )
    }

    private func readStringProperty(_ key: String, from entry: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
    }

    private func readRegistryPath(for entry: io_registry_entry_t) -> String {
        var pathBuffer = [CChar](repeating: 0, count: 512)
        let status = IORegistryEntryGetPath(entry, kIOServicePlane, &pathBuffer)
        guard status == kIOReturnSuccess else { return "" }
        return String(cString: pathBuffer)
    }

    private func readDDCLuminanceLocked(avService: CFTypeRef) -> DDCProtocol.LuminanceReply? {
        guard let ioAVServiceWriteI2C, let ioAVServiceReadI2C else { return nil }

        var request = DDCProtocol.makeGetLuminancePacket()
        var reply = [UInt8](repeating: 0, count: 11)

        for attempt in 0..<3 {
            var writeSucceeded = false
            for cycle in 0..<2 {
                let status = ioAVServiceWriteI2C(
                    avService,
                    DDCProtocol.chipAddress,
                    DDCProtocol.writeDataAddress,
                    &request,
                    UInt32(request.count)
                )
                if status == kIOReturnSuccess {
                    writeSucceeded = true
                }
                if cycle == 0 {
                    usleep(10_000)
                }
            }

            if !writeSucceeded {
                if attempt < 2 {
                    usleep(20_000)
                }
                continue
            }

            usleep(45_000)
            for idx in reply.indices {
                reply[idx] = 0
            }

            let readStatus = ioAVServiceReadI2C(
                avService,
                DDCProtocol.chipAddress,
                DDCProtocol.readDataAddress,
                &reply,
                UInt32(reply.count)
            )
            if readStatus == kIOReturnSuccess,
               let parsed = DDCProtocol.parseLuminanceReply(reply) {
                return parsed
            }

            if attempt < 2 {
                usleep(20_000)
            }
        }

        return nil
    }

    private func writeDDCLuminanceLocked(
        avService: CFTypeRef,
        level: Double,
        maxValue: Int
    ) -> Bool {
        guard let ioAVServiceWriteI2C else { return false }

        var packet = DDCProtocol.makeSetLuminancePacket(level: level, maxValue: maxValue)
        var writeSucceeded = false
        for cycle in 0..<2 {
            let status = ioAVServiceWriteI2C(
                avService,
                DDCProtocol.chipAddress,
                DDCProtocol.writeDataAddress,
                &packet,
                UInt32(packet.count)
            )
            if status == kIOReturnSuccess {
                writeSucceeded = true
            }
            if cycle == 0 {
                usleep(10_000)
            }
        }
        return writeSucceeded
    }

    private func applySoftwareGammaLocked(displayID: CGDirectDisplayID, level: Double) {
        var table = DDCProtocol.makeSoftwareGammaTable(level: level)
        _ = CGSetDisplayTransferByTable(displayID, UInt32(table.count), &table, &table, &table)
        softwareGammaLevels[displayID] = level
    }

    private func clearSoftwareGammaIfAppliedLocked(displayID: CGDirectDisplayID) {
        guard softwareGammaLevels.removeValue(forKey: displayID) != nil else { return }
        var identity = DDCProtocol.makeSoftwareGammaTable(level: 1.0)
        _ = CGSetDisplayTransferByTable(displayID, UInt32(identity.count), &identity, &identity, &identity)
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
