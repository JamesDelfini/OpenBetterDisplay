import CoreGraphics
import Foundation

public enum BrightnessBackendUsed: String, Equatable, Sendable {
    case nativeAppleBacklight
    case hardwareDDC
    case softwareGamma
}

public struct BrightnessReading: Equatable, Sendable {
    public var level: Double
    public var backend: BrightnessBackendUsed

    public init(level: Double, backend: BrightnessBackendUsed) {
        self.level = level
        self.backend = backend
    }
}

public struct RawDisplayMode: Equatable, Sendable {
    public var modeID: Int32
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double
    public var isUsableForDesktopGUI: Bool
    public var isNative: Bool
    public var bitsPerSample: Int
    public var isDefault: Bool
    public var isStretched: Bool
    public var isVRR: Bool
    public var isProMotion: Bool
    public var minRefreshRate: Double?

    public init(
        modeID: Int32,
        width: Int,
        height: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        refreshRate: Double = 60.0,
        isUsableForDesktopGUI: Bool = true,
        isNative: Bool = false,
        bitsPerSample: Int = 8,
        isDefault: Bool = false,
        isStretched: Bool = false,
        isVRR: Bool = false,
        isProMotion: Bool = false,
        minRefreshRate: Double? = nil
    ) {
        self.modeID = modeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth ?? width
        self.pixelHeight = pixelHeight ?? height
        self.refreshRate = refreshRate
        self.isUsableForDesktopGUI = isUsableForDesktopGUI
        self.isNative = isNative
        self.bitsPerSample = bitsPerSample
        self.isDefault = isDefault
        self.isStretched = isStretched
        self.isVRR = isVRR
        self.isProMotion = isProMotion
        self.minRefreshRate = minRefreshRate
    }
}

public struct RawDisplayInfo: Equatable, Sendable {
    public var displayID: UInt32
    public var name: String
    public var isBuiltIn: Bool
    public var isMain: Bool
    public var isActive: Bool
    public var vendorID: UInt32
    public var modelID: UInt32
    public var serialNumber: UInt32
    public var currentModeID: Int32
    public var modes: [RawDisplayMode]
    public var bounds: CGRect

    public init(
        displayID: UInt32,
        name: String,
        isBuiltIn: Bool,
        isMain: Bool,
        isActive: Bool = true,
        vendorID: UInt32 = 0,
        modelID: UInt32 = 0,
        serialNumber: UInt32 = 0,
        currentModeID: Int32 = 0,
        modes: [RawDisplayMode] = [],
        bounds: CGRect = .zero
    ) {
        self.displayID = displayID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
        self.isActive = isActive
        self.vendorID = vendorID
        self.modelID = modelID
        self.serialNumber = serialNumber
        self.currentModeID = currentModeID
        self.modes = modes
        self.bounds = bounds
    }
}

public enum ExpandedPopoverSection: Equatable, Sendable {
    case displayMode(UInt32)
    case refreshRate(UInt32)
    case mainDisplay(UInt32)
    case hotkeys

    public var displayID: UInt32? {
        switch self {
        case .displayMode(let id), .refreshRate(let id), .mainDisplay(let id):
            return id
        case .hotkeys:
            return nil
        }
    }
}

public enum DisplayModeScalingTier: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case hiDPI
    case loDPI

    public var label: String {
        switch self {
        case .hiDPI:
            return "HiDPI"
        case .loDPI:
            return "LoDPI"
        }
    }
}

public struct DisplayModeFilterCriteria: Codable, Equatable, Hashable, Sendable {
    public var aspectRatios: Set<String>
    public var refreshRates: Set<String>
    public var colorDepths: Set<Int>
    public var scalingTiers: Set<DisplayModeScalingTier>

    public static let unrestricted = DisplayModeFilterCriteria()

    public init(
        aspectRatios: Set<String> = [],
        refreshRates: Set<String> = [],
        colorDepths: Set<Int> = [],
        scalingTiers: Set<DisplayModeScalingTier> = []
    ) {
        self.aspectRatios = aspectRatios
        self.refreshRates = refreshRates
        self.colorDepths = colorDepths
        self.scalingTiers = scalingTiers
    }

    public var isUnrestricted: Bool {
        aspectRatios.isEmpty
            && refreshRates.isEmpty
            && colorDepths.isEmpty
            && scalingTiers.isEmpty
    }
}

public enum DisplayModeFilterChip: Equatable, Hashable, Sendable {
    case aspectRatio(String)
    case refreshRate(String)
    case colorDepth(Int)
    case scaling(DisplayModeScalingTier)
}

public struct DisplayModeFilterOptions: Equatable, Sendable {
    public var aspectRatios: [String]
    public var refreshRates: [String]
    public var colorDepths: [Int]
    public var scalingTiers: [DisplayModeScalingTier]

    public init(
        aspectRatios: [String] = [],
        refreshRates: [String] = [],
        colorDepths: [Int] = [],
        scalingTiers: [DisplayModeScalingTier] = []
    ) {
        self.aspectRatios = aspectRatios
        self.refreshRates = refreshRates
        self.colorDepths = colorDepths
        self.scalingTiers = scalingTiers
    }

    public var isEmpty: Bool {
        aspectRatios.isEmpty
            && refreshRates.isEmpty
            && colorDepths.isEmpty
            && scalingTiers.isEmpty
    }

    public func contains(_ chip: DisplayModeFilterChip) -> Bool {
        switch chip {
        case .aspectRatio(let label):
            return aspectRatios.contains(label)
        case .refreshRate(let label):
            return refreshRates.contains(label)
        case .colorDepth(let bits):
            return colorDepths.contains(bits)
        case .scaling(let tier):
            return scalingTiers.contains(tier)
        }
    }
}

public struct DisplayModeFilterState: Equatable, Sendable {
    public var availableOptions: DisplayModeFilterOptions
    public var activeCriteria: DisplayModeFilterCriteria
    public var isCustomized: Bool

    public init(
        availableOptions: DisplayModeFilterOptions = DisplayModeFilterOptions(),
        activeCriteria: DisplayModeFilterCriteria = DisplayModeFilterCriteria(),
        isCustomized: Bool = false
    ) {
        self.availableOptions = availableOptions
        self.activeCriteria = activeCriteria
        self.isCustomized = isCustomized
    }

    public var isShowingAll: Bool {
        isCustomized && activeCriteria.isUnrestricted
    }

    public func isChipSelected(_ chip: DisplayModeFilterChip) -> Bool {
        switch chip {
        case .aspectRatio(let label):
            return activeCriteria.aspectRatios.contains(label)
        case .refreshRate(let label):
            return activeCriteria.refreshRates.contains(label)
        case .colorDepth(let bits):
            return activeCriteria.colorDepths.contains(bits)
        case .scaling(let tier):
            return activeCriteria.scalingTiers.contains(tier)
        }
    }
}

public struct DisplayModeOption: Equatable, Identifiable, Sendable {
    public var modeID: Int32
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double
    public var bitsPerSample: Int
    public var isHiDPI: Bool
    public var isDefault: Bool
    public var isNative: Bool
    public var isVRR: Bool
    public var isProMotion: Bool
    public var minRefreshRate: Double?
    public var aspectRatioLabel: String
    public var refreshRateLabel: String?
    public var colorDepthLabel: String
    public var resolutionLabel: String

    public var id: Int32 { modeID }

    public var scalingTier: DisplayModeScalingTier {
        isHiDPI ? .hiDPI : .loDPI
    }

    public init(
        modeID: Int32,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        bitsPerSample: Int,
        isHiDPI: Bool,
        isDefault: Bool,
        isNative: Bool,
        isVRR: Bool = false,
        isProMotion: Bool = false,
        minRefreshRate: Double? = nil,
        aspectRatioLabel: String,
        refreshRateLabel: String?,
        colorDepthLabel: String,
        resolutionLabel: String
    ) {
        self.modeID = modeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.bitsPerSample = bitsPerSample
        self.isHiDPI = isHiDPI
        self.isDefault = isDefault
        self.isNative = isNative
        self.isVRR = isVRR
        self.isProMotion = isProMotion
        self.minRefreshRate = minRefreshRate
        self.aspectRatioLabel = aspectRatioLabel
        self.refreshRateLabel = refreshRateLabel
        self.colorDepthLabel = colorDepthLabel
        self.resolutionLabel = resolutionLabel
    }
}

public struct RefreshRateOption: Equatable, Identifiable, Sendable {
    public var modeID: Int32
    public var refreshRate: Double
    public var minRefreshRate: Double?
    public var isVRR: Bool
    public var isProMotion: Bool
    public var isNTSC: Bool
    public var label: String
    public var shortLabel: String

    public var id: Int32 { modeID }

    public init(
        modeID: Int32,
        refreshRate: Double,
        minRefreshRate: Double? = nil,
        isVRR: Bool = false,
        isProMotion: Bool = false,
        isNTSC: Bool = false,
        label: String,
        shortLabel: String
    ) {
        self.modeID = modeID
        self.refreshRate = refreshRate
        self.minRefreshRate = minRefreshRate
        self.isVRR = isVRR
        self.isProMotion = isProMotion
        self.isNTSC = isNTSC
        self.label = label
        self.shortLabel = shortLabel
    }
}

/// Persisted snapshot of a Favorite Mode so it can be recalled across `modeID` shifts.
public struct FavoriteModeRecord: Codable, Equatable, Sendable {
    public var modeID: Int32
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double
    public var bitsPerSample: Int

    public init(
        modeID: Int32,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        bitsPerSample: Int
    ) {
        self.modeID = modeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.bitsPerSample = bitsPerSample
    }

    public init(mode: DisplayModeOption) {
        self.init(
            modeID: mode.modeID,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate,
            bitsPerSample: mode.bitsPerSample
        )
    }
}

/// Resolved Favorite Mode slot (`1`–`5`) exposed on `DisplayState`.
public struct FavoriteModeSlot: Equatable, Identifiable, Sendable {
    public var slot: Int
    public var record: FavoriteModeRecord
    public var resolvedMode: DisplayModeOption?

    public var id: Int { slot }

    public var isAvailable: Bool {
        resolvedMode != nil
    }

    public func matches(modeID: Int32) -> Bool {
        if let resolvedMode {
            return resolvedMode.modeID == modeID
        }
        return record.modeID == modeID
    }

    public init(slot: Int, record: FavoriteModeRecord, resolvedMode: DisplayModeOption?) {
        self.slot = slot
        self.record = record
        self.resolvedMode = resolvedMode
    }
}

public enum DisplayToggleLockReason: Equatable, Sendable {
    case mainDisplay
    case lastActiveDisplay

    public var tooltip: String {
        switch self {
        case .mainDisplay:
            return "Cannot turn off the Main Display. Set another display as Main first."
        case .lastActiveDisplay:
            return "Cannot turn off the last remaining active display."
        }
    }
}

public struct DisplayState: Equatable, Identifiable, Sendable {
    public var displayID: UInt32
    public var name: String
    public var isBuiltIn: Bool
    public var isMain: Bool
    public var isEnabled: Bool
    public var canToggleOff: Bool
    public var brightness: Double
    public var brightnessBackend: BrightnessBackendUsed
    public var availableModes: [DisplayModeOption]
    public var filteredModes: [DisplayModeOption]
    public var modeFilterState: DisplayModeFilterState
    public var defaultMode: DisplayModeOption?
    public var nativeMode: DisplayModeOption?
    public var favoriteModes: [FavoriteModeSlot]
    public var currentModeID: Int32
    public var currentModeOption: DisplayModeOption?
    public var bounds: CGRect

    public var id: UInt32 { displayID }

    public var symbolName: String {
        isBuiltIn ? "laptopcomputer" : "display"
    }

    public var canSetAsMain: Bool {
        isEnabled && !isMain
    }

    public var brightnessPercentage: Int {
        Int((brightness * 100.0).rounded())
    }

    public var resolutionLabel: String {
        if let current = availableModes.first(where: { $0.modeID == currentModeID }) {
            return current.resolutionLabel
        }
        return currentModeOption?.resolutionLabel ?? ""
    }

    public var refreshRateLabel: String {
        if let current = availableModes.first(where: { $0.modeID == currentModeID }),
            let label = current.refreshRateLabel
        {
            return label
        }
        return currentModeOption?.refreshRateLabel ?? ""
    }

    public var refreshRateOptions: [RefreshRateOption] {
        let active = availableModes.first(where: { $0.modeID == currentModeID }) ?? currentModeOption
        return DisplayModeFilter.refreshRateOptions(for: active, in: availableModes)
    }

    public func favoriteMode(forSlot slot: Int) -> FavoriteModeSlot? {
        favoriteModes.first(where: { $0.slot == slot })
    }

    public func isFavorited(modeID: Int32) -> Bool {
        favoriteModes.contains { slotEntry in
            slotEntry.matches(modeID: modeID)
        }
    }

    public init(
        displayID: UInt32,
        name: String,
        isBuiltIn: Bool = false,
        isMain: Bool = false,
        isEnabled: Bool = true,
        canToggleOff: Bool = false,
        brightness: Double = 1.0,
        brightnessBackend: BrightnessBackendUsed = .hardwareDDC,
        availableModes: [DisplayModeOption] = [],
        filteredModes: [DisplayModeOption]? = nil,
        modeFilterState: DisplayModeFilterState = DisplayModeFilterState(),
        defaultMode: DisplayModeOption? = nil,
        nativeMode: DisplayModeOption? = nil,
        favoriteModes: [FavoriteModeSlot] = [],
        currentModeID: Int32 = 0,
        currentModeOption: DisplayModeOption? = nil,
        bounds: CGRect = .zero
    ) {
        self.displayID = displayID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
        self.isEnabled = isEnabled
        self.canToggleOff = canToggleOff
        self.brightness = brightness
        self.brightnessBackend = brightnessBackend
        self.availableModes = availableModes
        self.filteredModes = filteredModes ?? availableModes
        self.modeFilterState = modeFilterState
        self.defaultMode = defaultMode
        self.nativeMode = nativeMode
        self.favoriteModes = favoriteModes
        self.currentModeID = currentModeID
        self.currentModeOption = currentModeOption
        self.bounds = bounds
    }
}
