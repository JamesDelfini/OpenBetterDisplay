import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics

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

public enum SkyLightDisplayModeDescription {
    public static let byteLength: Int32 = 212
    public static let displayModeDefaultFlag: UInt32 = 0x0000_0004
    public static let displayModeStretchedFlag: UInt32 = 0x0000_0800
    public static let displayModeNativeFlag: UInt32 = 0x0200_0000
    private static let displayModeValidAndSafeMask: UInt32 = 0x0000_0003
    private static let displayModeUnsafeFlag: UInt32 = 0x4000_0000
    private static let pixelEncodingOffset = 0x30
    private static let pixelEncodingLength = 128

    public static func parse(bytes: [UInt8]) -> RawDisplayMode? {
        guard bytes.count >= Int(byteLength) else { return nil }

        let modeNumber = readInt32LE(bytes, offset: 0x00)
        let flags = readUInt32LE(bytes, offset: 0x04)
        let width = Int(readUInt32LE(bytes, offset: 0x08))
        let height = Int(readUInt32LE(bytes, offset: 0x0C))
        let depth = readUInt32LE(bytes, offset: 0x10)
        let rawBitsPerSample = Int(readUInt32LE(bytes, offset: 0x1C))
        let integerFreq = readUInt32LE(bytes, offset: 0x24)
        let fixedRefreshRate = readUInt32LE(bytes, offset: 0xBC)
        let ioFlags = readUInt32LE(bytes, offset: 0xC0)
        let ioDisplayModeID = readInt32LE(bytes, offset: 0xC4)
        let rawPixelsWide = Int(readUInt32LE(bytes, offset: 0xC8))
        let rawPixelsHigh = Int(readUInt32LE(bytes, offset: 0xCC))
        let scale = Float(bitPattern: readUInt32LE(bytes, offset: 0xD0))

        guard width > 0, height > 0 else { return nil }

        let modeID = (ioDisplayModeID == 0 && modeNumber != 0) ? modeNumber : ioDisplayModeID
        let pixelWidth: Int
        if rawPixelsWide > 0 {
            pixelWidth = rawPixelsWide
        } else if scale > 1.0 {
            pixelWidth = Int((Double(width) * Double(scale)).rounded())
        } else {
            pixelWidth = width
        }

        let pixelHeight: Int
        if rawPixelsHigh > 0 {
            pixelHeight = rawPixelsHigh
        } else if scale > 1.0 {
            pixelHeight = Int((Double(height) * Double(scale)).rounded())
        } else {
            pixelHeight = height
        }

        let refreshRate: Double
        if fixedRefreshRate > 0 {
            refreshRate = Double(fixedRefreshRate) / 65536.0
        } else {
            refreshRate = Double(integerFreq)
        }

        let bitsPerSample = resolveBitsPerSample(rawField: rawBitsPerSample, bytes: bytes)
        let combinedFlags = ioFlags | flags
        let isDefault = (combinedFlags & displayModeDefaultFlag) != 0
        let isStretched = (combinedFlags & displayModeStretchedFlag) != 0
        let isNative = (combinedFlags & displayModeNativeFlag) != 0
        let isUsableForDesktopGUI =
            (ioFlags & displayModeValidAndSafeMask) == displayModeValidAndSafeMask
            && (flags & displayModeUnsafeFlag) == 0
            && !isStretched
            && width >= 720
            && height >= 720
            && max(Int(depth), rawBitsPerSample) >= 4

        return RawDisplayMode(
            modeID: modeID,
            width: width,
            height: height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            refreshRate: refreshRate,
            isUsableForDesktopGUI: isUsableForDesktopGUI,
            isNative: isNative,
            bitsPerSample: bitsPerSample,
            isDefault: isDefault,
            isStretched: isStretched
        )
    }

    private static func resolveBitsPerSample(rawField: Int, bytes: [UInt8]) -> Int {
        if rawField > 0 {
            return rawField
        }
        let redCount = parseRedChannelBitsFromPixelEncoding(bytes)
        return redCount >= 4 ? redCount : 8
    }

    private static func parseRedChannelBitsFromPixelEncoding(_ bytes: [UInt8]) -> Int {
        let start = pixelEncodingOffset
        let end = min(bytes.count, start + pixelEncodingLength)
        guard start < end else { return 0 }

        var count = 0
        for index in start..<end {
            let byte = bytes[index]
            if byte == 0 {
                break
            }
            if byte == UInt8(ascii: "R") {
                count += 1
            }
        }
        return count
    }

    private static func readUInt32LE(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readInt32LE(_ bytes: [UInt8], offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32LE(bytes, offset: offset))
    }
}

public final class MacOSDisplayDriver: DisplayDriver, @unchecked Sendable {
    private typealias CGSGetDisplayListFn =
        @convention(c) (
            UInt32,
            UnsafeMutablePointer<CGDirectDisplayID>?,
            UnsafeMutablePointer<UInt32>?
        ) -> CGError

    private typealias CGSConfigureDisplayEnabledFn =
        @convention(c) (
            CGDisplayConfigRef?,
            CGDirectDisplayID,
            Bool
        ) -> CGError

    private typealias CGSConfigureDisplayModeFn =
        @convention(c) (
            CGDisplayConfigRef?,
            CGDirectDisplayID,
            Int32
        ) -> CGError

    private typealias CGSGetNumberOfDisplayModesFn =
        @convention(c) (
            CGDirectDisplayID,
            UnsafeMutablePointer<Int32>
        ) -> CGError

    private typealias CGSGetDisplayModeDescriptionOfLengthFn =
        @convention(c) (
            CGDirectDisplayID,
            Int32,
            UnsafeMutableRawPointer,
            Int32
        ) -> CGError

    private typealias CGSGetCurrentDisplayModeFn =
        @convention(c) (
            CGDirectDisplayID,
            UnsafeMutablePointer<Int32>
        ) -> CGError

    private typealias CoreDisplayCreateInfoDictionaryFn =
        @convention(c) (
            CGDirectDisplayID
        ) -> Unmanaged<CFDictionary>?

    private typealias DisplayServicesCanChangeBrightnessFn =
        @convention(c) (
            CGDirectDisplayID
        ) -> Bool

    private typealias DisplayServicesGetBrightnessFn =
        @convention(c) (
            CGDirectDisplayID,
            UnsafeMutablePointer<Float>
        ) -> Int32

    private typealias DisplayServicesSetBrightnessFn =
        @convention(c) (
            CGDirectDisplayID,
            Float
        ) -> Int32

    private let cgsGetDisplayList: CGSGetDisplayListFn?
    private let cgsConfigureDisplayEnabled: CGSConfigureDisplayEnabledFn?
    private let cgsConfigureDisplayMode: CGSConfigureDisplayModeFn?
    private let cgsGetNumberOfDisplayModes: CGSGetNumberOfDisplayModesFn?
    private let cgsGetDisplayModeDescriptionOfLength: CGSGetDisplayModeDescriptionOfLengthFn?
    private let cgsGetCurrentDisplayMode: CGSGetCurrentDisplayModeFn?
    private let coreDisplayCreateInfoDictionary: CoreDisplayCreateInfoDictionaryFn?
    private let displayServicesCanChangeBrightness: DisplayServicesCanChangeBrightnessFn?
    private let displayServicesGetBrightness: DisplayServicesGetBrightnessFn?
    private let displayServicesSetBrightness: DisplayServicesSetBrightnessFn?

    private let stateLock = NSLock()
    private var softwareGammaLevels: [CGDirectDisplayID: Double] = [:]
    private let ddcClient: AppleSiliconDDCClient

    public init() {
        let skyLight = DynamicLibrary(path: "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")
        let getDisplayList: CGSGetDisplayListFn? = skyLight.symbol("CGSGetDisplayList")
        self.cgsGetDisplayList = getDisplayList
        self.cgsConfigureDisplayEnabled = skyLight.symbol("CGSConfigureDisplayEnabled")
        self.cgsConfigureDisplayMode = skyLight.symbol("CGSConfigureDisplayMode")
        self.cgsGetNumberOfDisplayModes = skyLight.symbol("CGSGetNumberOfDisplayModes")
        self.cgsGetDisplayModeDescriptionOfLength = skyLight.symbol("CGSGetDisplayModeDescriptionOfLength")
        self.cgsGetCurrentDisplayMode = skyLight.symbol("CGSGetCurrentDisplayMode")

        let coreDisplay = DynamicLibrary(path: "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay")
        let createInfoDict: CoreDisplayCreateInfoDictionaryFn? = coreDisplay.symbol("CoreDisplay_DisplayCreateInfoDictionary")
        self.coreDisplayCreateInfoDictionary = createInfoDict

        let displayServices = DynamicLibrary(path: "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")
        self.displayServicesCanChangeBrightness = displayServices.symbol("DisplayServicesCanChangeBrightness")
        self.displayServicesGetBrightness = displayServices.symbol("DisplayServicesGetBrightness")
        self.displayServicesSetBrightness = displayServices.symbol("DisplayServicesSetBrightness")

        let transport = IOAVServiceDDCTransport(
            matchTargetProvider: { displayID in
                Self.buildDisplayMatchTarget(
                    for: displayID,
                    coreDisplayCreateInfoDictionary: createInfoDict
                )
            },
            externalDisplayCountProvider: {
                Self.collectConnectedDisplayIDs(cgsGetDisplayList: getDisplayList)
                    .filter { CGDisplayIsBuiltin($0) == 0 }
                    .count
            }
        )
        self.ddcClient = AppleSiliconDDCClient(transport: transport)
    }

    public func fetchOnlineDisplays() -> [RawDisplayInfo] {
        let displayIDs = Self.collectConnectedDisplayIDs(cgsGetDisplayList: cgsGetDisplayList)
        let activeIDSet = Set(displayIDs)
        ddcClient.pruneDisplays(keeping: activeIDSet)
        stateLock.lock()
        softwareGammaLevels = softwareGammaLevels.filter { activeIDSet.contains($0.key) }
        stateLock.unlock()

        return displayIDs.map { displayID in
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let isMain = CGDisplayIsMain(displayID) != 0
            let isActive = CGDisplayIsActive(displayID) != 0
            let vendorID = CGDisplayVendorNumber(displayID)
            let modelID = CGDisplayModelNumber(displayID)
            let serialNumber = CGDisplaySerialNumber(displayID)
            let name = resolveDisplayName(
                for: displayID,
                isBuiltIn: isBuiltIn,
                vendorID: vendorID,
                modelID: modelID,
                serialNumber: serialNumber
            )
            let currentModeID = fetchCurrentModeID(for: displayID)
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
        try performDisplayConfiguration { configRef in
            let err = cgsConfigureDisplayEnabled(configRef, displayID, enabled)
            guard err == .success else {
                throw DisplayDriverError.configurationFailed(err.rawValue)
            }
        }
        ddcClient.invalidate(displayID: displayID)
        stateLock.lock()
        softwareGammaLevels.removeValue(forKey: displayID)
        stateLock.unlock()
    }

    public func setMainDisplay(_ displayID: UInt32) throws {
        guard CGDisplayIsActive(displayID) != 0 else {
            throw DisplayDriverError.configurationFailed(CGError.illegalArgument.rawValue)
        }

        let targetBounds = CGDisplayBounds(displayID)
        let offsetX = -Int32(targetBounds.origin.x.rounded())
        let offsetY = -Int32(targetBounds.origin.y.rounded())

        var activeIDs = Self.collectConnectedDisplayIDs(cgsGetDisplayList: cgsGetDisplayList)
            .filter { CGDisplayIsActive($0) != 0 }
        if !activeIDs.contains(displayID) {
            activeIDs.append(displayID)
        }

        try performDisplayConfiguration { configRef in
            let targetErr = CGConfigureDisplayOrigin(configRef, displayID, 0, 0)
            guard targetErr == .success else {
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
                    throw DisplayDriverError.configurationFailed(originErr.rawValue)
                }
            }
        }
    }

    public func getBrightness(_ displayID: UInt32) -> BrightnessReading {
        if let nativeLevel = readNativeAppleBacklight(displayID) {
            return BrightnessReading(level: nativeLevel, backend: .nativeAppleBacklight)
        }

        if CGDisplayIsBuiltin(displayID) != 0 {
            stateLock.lock()
            let level = softwareGammaLevels[displayID] ?? 1.0
            stateLock.unlock()
            return BrightnessReading(level: level, backend: .nativeAppleBacklight)
        }

        if let reply = ddcClient.readBrightness(for: displayID) {
            return BrightnessReading(level: reply.normalizedLevel, backend: .hardwareDDC)
        }

        stateLock.lock()
        let fallbackLevel = softwareGammaLevels[displayID] ?? 1.0
        stateLock.unlock()
        return BrightnessReading(level: fallbackLevel, backend: .softwareGamma)
    }

    public func setBrightness(_ displayID: UInt32, level: Double) -> BrightnessBackendUsed {
        let clamped = max(0.0, min(1.0, level))

        if writeNativeAppleBacklight(displayID, level: clamped) {
            clearSoftwareGammaIfApplied(displayID: displayID)
            return .nativeAppleBacklight
        }

        if CGDisplayIsBuiltin(displayID) == 0,
            ddcClient.writeBrightness(for: displayID, level: clamped)
        {
            clearSoftwareGammaIfApplied(displayID: displayID)
            return .hardwareDDC
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

        try performDisplayConfiguration { configRef in
            var configErr: CGError = .failure
            if let targetMode {
                configErr = CGConfigureDisplayWithDisplayMode(configRef, displayID, targetMode, nil)
            }
            if configErr != .success, let cgsConfigureDisplayMode {
                configErr = cgsConfigureDisplayMode(configRef, displayID, modeID)
            }
            guard configErr == .success else {
                if targetMode == nil {
                    throw DisplayDriverError.modeNotFound(modeID)
                }
                throw DisplayDriverError.configurationFailed(configErr.rawValue)
            }
        }
    }

    public func resetSoftwareGamma() {
        stateLock.lock()
        softwareGammaLevels.removeAll()
        stateLock.unlock()
        CGDisplayRestoreColorSyncSettings()
    }

    // MARK: - CoreGraphics Configuration Transaction

    private func performDisplayConfiguration(
        _ configure: (CGDisplayConfigRef) throws -> Void
    ) throws {
        var configRef: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&configRef)
        guard beginErr == .success, let configRef else {
            throw DisplayDriverError.configurationFailed(beginErr.rawValue)
        }
        do {
            try configure(configRef)
        } catch {
            CGCancelDisplayConfiguration(configRef)
            throw error
        }
        let completeErr = CGCompleteDisplayConfiguration(configRef, .forSession)
        guard completeErr == .success else {
            throw DisplayDriverError.configurationFailed(completeErr.rawValue)
        }
    }

    // MARK: - Discovery, Naming & Mode Queries

    private static func collectConnectedDisplayIDs(
        cgsGetDisplayList: CGSGetDisplayListFn?
    ) -> [CGDirectDisplayID] {
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
        modelID: UInt32,
        serialNumber: UInt32
    ) -> String {
        if isBuiltIn {
            return "Built-in Display"
        }

        if let coreDisplayCreateInfoDictionary,
            let unmanagedDict = coreDisplayCreateInfoDictionary(displayID),
            let dict = unmanagedDict.takeRetainedValue() as? [String: Any],
            let productName = DisplayNameFormatter.extractProductName(from: dict)
        {
            return productName
        }

        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[screenNumberKey] as? NSNumber,
                number.uint32Value == displayID
            {
                let localized = screen.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !localized.isEmpty {
                    return localized
                }
            }
        }

        if let ioKitEDIDName = readIOKitDisplayConnectName(
            vendorID: vendorID,
            modelID: modelID,
            serialNumber: serialNumber
        ) {
            return ioKitEDIDName
        }

        if let avServiceEDIDName = ddcClient.readEDIDProductName(for: displayID) {
            return avServiceEDIDName
        }

        return DisplayNameFormatter.fallbackExternalName(vendorID: vendorID, modelID: modelID)
    }

    private func readIOKitDisplayConnectName(
        vendorID: UInt32,
        modelID: UInt32,
        serialNumber: UInt32
    ) -> String? {
        var iterator: io_iterator_t = 0
        let matchResult = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        guard matchResult == kIOReturnSuccess, iterator != 0 else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            guard
                let info = IODisplayCreateInfoDictionary(
                    service,
                    IOOptionBits(kIODisplayOnlyPreferredName)
                )?.takeRetainedValue() as? [String: Any]
            else {
                continue
            }

            let entryVendor = (info[kDisplayVendorID] as? NSNumber)?.uint32Value ?? 0
            let entryProduct = (info[kDisplayProductID] as? NSNumber)?.uint32Value ?? 0
            let entrySerial = (info[kDisplaySerialNumber] as? NSNumber)?.uint32Value ?? 0

            if vendorID != 0, entryVendor != vendorID { continue }
            if modelID != 0, entryProduct != modelID { continue }
            if serialNumber != 0, entrySerial != 0, entrySerial != serialNumber { continue }

            if let preferredName = DisplayNameFormatter.extractProductName(from: info) {
                return preferredName
            }
            if let edidData = info[kIODisplayEDIDKey] as? Data,
                let parsedName = DDCProtocol.parseEDID(edidData)?.productName?.trimmingCharacters(in: .whitespacesAndNewlines),
                !parsedName.isEmpty
            {
                return parsedName
            }
        }

        return nil
    }

    private func fetchCurrentModeID(for displayID: CGDirectDisplayID) -> Int32 {
        if let cgCurrentMode = CGDisplayCopyDisplayMode(displayID) {
            return cgCurrentMode.ioDisplayModeID
        }
        return querySkyLightCurrentModeID(for: displayID) ?? 0
    }

    private func querySkyLightCurrentModeID(for displayID: CGDirectDisplayID) -> Int32? {
        guard let cgsGetCurrentDisplayMode else { return nil }
        var currentModeNumber: Int32 = -1
        guard cgsGetCurrentDisplayMode(displayID, &currentModeNumber) == .success,
            currentModeNumber >= 0
        else {
            return nil
        }
        if let cgsGetDisplayModeDescriptionOfLength {
            var buffer = [UInt8](repeating: 0, count: Int(SkyLightDisplayModeDescription.byteLength))
            let err = buffer.withUnsafeMutableBytes { rawBuffer -> CGError in
                guard let baseAddress = rawBuffer.baseAddress else { return .failure }
                return cgsGetDisplayModeDescriptionOfLength(
                    displayID,
                    currentModeNumber,
                    baseAddress,
                    SkyLightDisplayModeDescription.byteLength
                )
            }
            if err == .success, let parsed = SkyLightDisplayModeDescription.parse(bytes: buffer) {
                return parsed.modeID
            }
        }
        return currentModeNumber
    }

    public static func mergeDisplayModes(
        cgModes: [RawDisplayMode],
        skyLightModes: [RawDisplayMode]
    ) -> [RawDisplayMode] {
        var mergedByID: [Int32: RawDisplayMode] = [:]
        var orderedIDs: [Int32] = []

        for mode in cgModes {
            if mergedByID[mode.modeID] == nil {
                orderedIDs.append(mode.modeID)
            }
            mergedByID[mode.modeID] = mode
        }

        for skyLightMode in skyLightModes {
            if var existing = mergedByID[skyLightMode.modeID] {
                if skyLightMode.bitsPerSample > 0 {
                    existing.bitsPerSample = skyLightMode.bitsPerSample
                }
                existing.isDefault = existing.isDefault || skyLightMode.isDefault
                existing.isNative = existing.isNative || skyLightMode.isNative
                existing.isStretched = existing.isStretched || skyLightMode.isStretched
                existing.isUsableForDesktopGUI =
                    existing.isUsableForDesktopGUI
                    && skyLightMode.isUsableForDesktopGUI
                    && !existing.isStretched
                if existing.refreshRate <= 0, skyLightMode.refreshRate > 0 {
                    existing.refreshRate = skyLightMode.refreshRate
                }
                mergedByID[skyLightMode.modeID] = existing
            } else {
                orderedIDs.append(skyLightMode.modeID)
                mergedByID[skyLightMode.modeID] = skyLightMode
            }
        }

        return orderedIDs.compactMap { mergedByID[$0] }
    }

    private func fetchDisplayModes(for displayID: CGDirectDisplayID) -> [RawDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        var cgModes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
        if let currentMode = CGDisplayCopyDisplayMode(displayID),
            !cgModes.contains(where: { $0.ioDisplayModeID == currentMode.ioDisplayModeID })
        {
            cgModes.append(currentMode)
        }

        let mappedCGModes = cgModes.map { mode in
            let ioFlags = mode.ioFlags
            let isStretched = (ioFlags & SkyLightDisplayModeDescription.displayModeStretchedFlag) != 0
            return RawDisplayMode(
                modeID: mode.ioDisplayModeID,
                width: mode.width,
                height: mode.height,
                pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate,
                isUsableForDesktopGUI: mode.isUsableForDesktopGUI() && !isStretched && mode.width >= 720 && mode.height >= 720,
                isNative: (ioFlags & SkyLightDisplayModeDescription.displayModeNativeFlag) != 0,
                bitsPerSample: 8,
                isDefault: (ioFlags & SkyLightDisplayModeDescription.displayModeDefaultFlag) != 0,
                isStretched: isStretched
            )
        }

        let skyLightModes = fetchSkyLightDisplayModes(for: displayID)
        return Self.mergeDisplayModes(cgModes: mappedCGModes, skyLightModes: skyLightModes)
    }

    private func fetchSkyLightDisplayModes(for displayID: CGDirectDisplayID) -> [RawDisplayMode] {
        guard let cgsGetNumberOfDisplayModes,
            let cgsGetDisplayModeDescriptionOfLength
        else {
            return []
        }

        var modeCount: Int32 = 0
        guard cgsGetNumberOfDisplayModes(displayID, &modeCount) == .success,
            modeCount > 0
        else {
            return []
        }

        let boundedCount = min(modeCount, 4096)
        var buffer = [UInt8](repeating: 0, count: Int(SkyLightDisplayModeDescription.byteLength))
        var modes: [RawDisplayMode] = []
        modes.reserveCapacity(Int(boundedCount))

        for index in 0..<boundedCount {
            let err = buffer.withUnsafeMutableBytes { rawBuffer -> CGError in
                guard let baseAddress = rawBuffer.baseAddress else { return .failure }
                return cgsGetDisplayModeDescriptionOfLength(
                    displayID,
                    index,
                    baseAddress,
                    SkyLightDisplayModeDescription.byteLength
                )
            }
            if err == .success, let parsed = SkyLightDisplayModeDescription.parse(bytes: buffer) {
                modes.append(parsed)
            }
        }

        return modes
    }

    private static func buildDisplayMatchTarget(
        for displayID: CGDirectDisplayID,
        coreDisplayCreateInfoDictionary: CoreDisplayCreateInfoDictionaryFn?
    ) -> DDCProtocol.DisplayMatchTarget {
        let vendorID = CGDisplayVendorNumber(displayID)
        let modelID = CGDisplayModelNumber(displayID)
        let serialNumber = CGDisplaySerialNumber(displayID)

        var productName: String?
        var weekOfManufacture: Int?
        var yearOfManufacture: Int?
        var ioDisplayLocation: String?
        var alphanumericSerial: String?

        if let coreDisplayCreateInfoDictionary,
            let unmanagedDict = coreDisplayCreateInfoDictionary(displayID),
            let dict = unmanagedDict.takeRetainedValue() as? [String: Any]
        {
            productName = DisplayNameFormatter.extractProductName(from: dict)
            weekOfManufacture = (dict["DisplayWeekManufacture"] as? NSNumber)?.intValue
            yearOfManufacture = (dict["DisplayYearManufacture"] as? NSNumber)?.intValue
            ioDisplayLocation = dict["IODisplayLocation"] as? String
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
                    let alphaSerial = productAttributes["AlphanumericSerialNumber"] as? String
                {
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

    // MARK: - Tier 1 (DisplayServices) & Tier 3 (Software Gamma)

    private func supportsNativeAppleBacklight(_ displayID: CGDirectDisplayID) -> Bool {
        if let displayServicesCanChangeBrightness {
            return displayServicesCanChangeBrightness(displayID)
        }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    private func readNativeAppleBacklight(_ displayID: CGDirectDisplayID) -> Double? {
        guard supportsNativeAppleBacklight(displayID),
            let displayServicesGetBrightness
        else {
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
            let displayServicesSetBrightness
        else {
            return false
        }
        return displayServicesSetBrightness(displayID, Float(level)) == 0
    }

    private func applySoftwareGamma(displayID: CGDirectDisplayID, level: Double) {
        stateLock.lock()
        var table = DDCProtocol.makeSoftwareGammaTable(level: level)
        _ = CGSetDisplayTransferByTable(displayID, UInt32(table.count), &table, &table, &table)
        softwareGammaLevels[displayID] = level
        stateLock.unlock()
    }

    private func clearSoftwareGammaIfApplied(displayID: CGDirectDisplayID) {
        stateLock.lock()
        let hadGamma = softwareGammaLevels.removeValue(forKey: displayID) != nil
        if hadGamma {
            var identity = DDCProtocol.makeSoftwareGammaTable(level: 1.0)
            _ = CGSetDisplayTransferByTable(displayID, UInt32(identity.count), &identity, &identity, &identity)
        }
        stateLock.unlock()
    }
}
