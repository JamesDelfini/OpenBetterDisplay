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
    public var isVariableRefreshRate: Bool
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
        isVariableRefreshRate: Bool = false,
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
        self.isVariableRefreshRate = isVariableRefreshRate
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

/// Typed filter key representing a Display Mode aspect ratio (such as `16:9`, `16:10`, or `15.4:10`).
public struct AspectRatioFilterKey: Codable, Equatable, Hashable, Sendable, Comparable {
    public let widthTenths: Int
    public let heightTenths: Int

    private enum CodingKeys: String, CodingKey {
        case widthTenths
        case heightTenths
    }

    public init(_ width: Int, _ height: Int) {
        self.widthTenths = max(0, width) * 10
        self.heightTenths = max(0, height) * 10
    }

    public init(widthTenths: Int, heightTenths: Int) {
        self.widthTenths = max(0, widthTenths)
        self.heightTenths = max(0, heightTenths)
    }

    public init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
            let rawString = try? singleValue.decode(String.self)
        {
            guard let parsed = Self.parse(label: rawString) else {
                throw DecodingError.dataCorruptedError(
                    in: singleValue,
                    debugDescription: "Invalid aspect ratio filter key string: \(rawString)"
                )
            }
            self = parsed
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let widthTenths = try container.decode(Int.self, forKey: .widthTenths)
        let heightTenths = try container.decode(Int.self, forKey: .heightTenths)
        guard widthTenths > 0, heightTenths > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .widthTenths,
                in: container,
                debugDescription: "Aspect ratio components must be positive."
            )
        }
        self.init(widthTenths: widthTenths, heightTenths: heightTenths)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(widthTenths, forKey: .widthTenths)
        try container.encode(heightTenths, forKey: .heightTenths)
    }

    public var label: String {
        guard widthTenths > 0, heightTenths > 0 else { return "—" }
        return "\(Self.formatComponent(widthTenths)):\(Self.formatComponent(heightTenths))"
    }

    public static func < (lhs: AspectRatioFilterKey, rhs: AspectRatioFilterKey) -> Bool {
        let lhsCross = Int64(lhs.widthTenths) * Int64(rhs.heightTenths)
        let rhsCross = Int64(rhs.widthTenths) * Int64(lhs.heightTenths)
        if lhsCross != rhsCross {
            return lhsCross < rhsCross
        }
        return lhs.widthTenths < rhs.widthTenths
    }

    static func parse(label: String) -> AspectRatioFilterKey? {
        let parts = label.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
            let widthTenths = parseTenthsComponent(String(parts[0])),
            let heightTenths = parseTenthsComponent(String(parts[1]))
        else {
            return nil
        }
        return AspectRatioFilterKey(widthTenths: widthTenths, heightTenths: heightTenths)
    }

    private static func parseTenthsComponent(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 1, let integer = Int(parts[0]), integer > 0 {
            return integer * 10
        }
        if parts.count == 2,
            let integer = Int(parts[0]),
            integer >= 0,
            parts[1].count == 1,
            let tenths = Int(parts[1]),
            tenths >= 0
        {
            let combined = integer * 10 + tenths
            return combined > 0 ? combined : nil
        }
        if let decimal = Double(trimmed), decimal > 0 {
            let scaled = Int((decimal * 10.0).rounded())
            return scaled > 0 ? scaled : nil
        }
        return nil
    }

    private static func formatComponent(_ tenths: Int) -> String {
        if tenths % 10 == 0 {
            return "\(tenths / 10)"
        }
        return "\(tenths / 10).\(tenths % 10)"
    }
}

/// Typed filter key representing a Display Mode refresh rate (fixed Hz or Variable Refresh Rate range).
public struct RefreshRateFilterKey: Codable, Equatable, Hashable, Sendable, Comparable {
    public let isVariableRefreshRate: Bool
    public let minHundredths: Int?
    public let maxHundredths: Int

    private enum CodingKeys: String, CodingKey {
        case isVariableRefreshRate
        case minHundredths
        case maxHundredths
    }

    public init(
        isVariableRefreshRate: Bool = false,
        minRefreshRate: Double? = nil,
        maxRefreshRate: Double
    ) {
        let normalized = DisplayModeFilter.normalizeVariableRefreshRate(
            isVariableRefreshRate: isVariableRefreshRate,
            minRefreshRate: minRefreshRate,
            maxRefreshRate: maxRefreshRate
        )
        self.isVariableRefreshRate = normalized.isVariableRefreshRate
        self.maxHundredths = max(0, Int((maxRefreshRate * 100.0).rounded()))
        self.minHundredths = normalized.minRefreshRate.map { max(0, Int(($0 * 100.0).rounded())) }
    }

    public init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
            let rawString = try? singleValue.decode(String.self)
        {
            guard let parsed = Self.parse(label: rawString) else {
                throw DecodingError.dataCorruptedError(
                    in: singleValue,
                    debugDescription: "Invalid refresh rate filter key string: \(rawString)"
                )
            }
            self = parsed
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isVariable = try container.decode(Bool.self, forKey: .isVariableRefreshRate)
        let maxHundredths = try container.decode(Int.self, forKey: .maxHundredths)
        let minHundredths = try container.decodeIfPresent(Int.self, forKey: .minHundredths)
        guard maxHundredths > 50 else {
            throw DecodingError.dataCorruptedError(
                forKey: .maxHundredths,
                in: container,
                debugDescription: "Refresh rate must be greater than 0.5 Hz."
            )
        }
        self.init(
            isVariableRefreshRate: isVariable,
            minRefreshRate: minHundredths.map { Double($0) / 100.0 },
            maxRefreshRate: Double(maxHundredths) / 100.0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isVariableRefreshRate, forKey: .isVariableRefreshRate)
        try container.encodeIfPresent(minHundredths, forKey: .minHundredths)
        try container.encode(maxHundredths, forKey: .maxHundredths)
    }

    public static func fixed(_ refreshRate: Double) -> RefreshRateFilterKey {
        RefreshRateFilterKey(isVariableRefreshRate: false, minRefreshRate: nil, maxRefreshRate: refreshRate)
    }

    public static func variable(min minRefreshRate: Double? = nil, max maxRefreshRate: Double) -> RefreshRateFilterKey {
        RefreshRateFilterKey(isVariableRefreshRate: true, minRefreshRate: minRefreshRate, maxRefreshRate: maxRefreshRate)
    }

    public var maxRefreshRate: Double {
        Double(maxHundredths) / 100.0
    }

    public var minRefreshRate: Double? {
        minHundredths.map { Double($0) / 100.0 }
    }

    public var label: String {
        guard let maxNumber = Self.formatRateNumber(hundredths: maxHundredths) else {
            return "—"
        }
        if isVariableRefreshRate {
            if let minHundredths,
                minHundredths < maxHundredths - 50,
                let minNumber = Self.formatRateNumber(hundredths: minHundredths)
            {
                return "\(minNumber)–\(maxNumber)Hz"
            }
            return "\(maxNumber)Hz (Variable)"
        }
        return "\(maxNumber)Hz"
    }

    public static func < (lhs: RefreshRateFilterKey, rhs: RefreshRateFilterKey) -> Bool {
        if lhs.maxHundredths != rhs.maxHundredths {
            return lhs.maxHundredths < rhs.maxHundredths
        }
        if lhs.isVariableRefreshRate != rhs.isVariableRefreshRate {
            return !lhs.isVariableRefreshRate && rhs.isVariableRefreshRate
        }
        let lhsMin = lhs.minHundredths ?? lhs.maxHundredths
        let rhsMin = rhs.minHundredths ?? rhs.maxHundredths
        return lhsMin < rhsMin
    }

    static func formatRateNumber(hundredths: Int) -> String? {
        guard hundredths > 50 else { return nil }
        if hundredths % 100 == 0 {
            return "\(hundredths / 100)"
        }
        return String(format: "%.2f", Double(hundredths) / 100.0)
    }

    static func parse(label: String) -> RefreshRateFilterKey? {
        var working = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return nil }

        var hasVariableSuffix = false
        if working.hasSuffix(" (Variable)") {
            hasVariableSuffix = true
            working = String(working.dropLast(" (Variable)".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if working.hasSuffix("Hz") || working.hasSuffix("hz") {
            working = String(working.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil
        }

        let rangeParts =
            working.contains("–")
            ? working.split(separator: "–", omittingEmptySubsequences: false)
            : working.split(separator: "-", omittingEmptySubsequences: false)
        if rangeParts.count == 2,
            let minRate = Double(rangeParts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
            let maxRate = Double(rangeParts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
            minRate > 0.5,
            maxRate > 0.5,
            minRate < maxRate - 0.5
        {
            return .variable(min: minRate, max: maxRate)
        }

        if let fixedOrMaxRate = Double(working), fixedOrMaxRate > 0.5 {
            return hasVariableSuffix ? .variable(min: nil, max: fixedOrMaxRate) : .fixed(fixedOrMaxRate)
        }

        return nil
    }
}

public struct DisplayModeFilterCriteria: Codable, Equatable, Hashable, Sendable {
    public var aspectRatios: Set<AspectRatioFilterKey>
    public var refreshRates: Set<RefreshRateFilterKey>
    public var colorDepths: Set<Int>
    public var scalingTiers: Set<DisplayModeScalingTier>

    private enum CodingKeys: String, CodingKey {
        case aspectRatios
        case refreshRates
        case colorDepths
        case scalingTiers
    }

    public static let unrestricted = DisplayModeFilterCriteria()

    public init(
        aspectRatios: Set<AspectRatioFilterKey> = [],
        refreshRates: Set<RefreshRateFilterKey> = [],
        colorDepths: Set<Int> = [],
        scalingTiers: Set<DisplayModeScalingTier> = []
    ) {
        self.aspectRatios = aspectRatios
        self.refreshRates = refreshRates
        self.colorDepths = colorDepths
        self.scalingTiers = scalingTiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aspectRatios = try container.decodeIfPresent(Set<AspectRatioFilterKey>.self, forKey: .aspectRatios) ?? []
        refreshRates = try container.decodeIfPresent(Set<RefreshRateFilterKey>.self, forKey: .refreshRates) ?? []
        colorDepths = try container.decodeIfPresent(Set<Int>.self, forKey: .colorDepths) ?? []
        scalingTiers = try container.decodeIfPresent(Set<DisplayModeScalingTier>.self, forKey: .scalingTiers) ?? []
    }

    public var isUnrestricted: Bool {
        aspectRatios.isEmpty
            && refreshRates.isEmpty
            && colorDepths.isEmpty
            && scalingTiers.isEmpty
    }
}

public enum DisplayModeFilterChip: Equatable, Hashable, Sendable {
    case aspectRatio(AspectRatioFilterKey)
    case refreshRate(RefreshRateFilterKey)
    case colorDepth(Int)
    case scaling(DisplayModeScalingTier)
}

public struct DisplayModeFilterOptions: Equatable, Sendable {
    public var aspectRatios: [AspectRatioFilterKey]
    public var refreshRates: [RefreshRateFilterKey]
    public var colorDepths: [Int]
    public var scalingTiers: [DisplayModeScalingTier]

    public init(
        aspectRatios: [AspectRatioFilterKey] = [],
        refreshRates: [RefreshRateFilterKey] = [],
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
        case .aspectRatio(let ratio):
            return aspectRatios.contains(ratio)
        case .refreshRate(let rate):
            return refreshRates.contains(rate)
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
        case .aspectRatio(let ratio):
            return activeCriteria.aspectRatios.contains(ratio)
        case .refreshRate(let rate):
            return activeCriteria.refreshRates.contains(rate)
        case .colorDepth(let bits):
            return activeCriteria.colorDepths.contains(bits)
        case .scaling(let tier):
            return activeCriteria.scalingTiers.contains(tier)
        }
    }
}

/// Bundled per-display Display Mode catalog passed across filter resolution seams.
public struct DisplayModeContext: Equatable, Sendable {
    public var raw: RawDisplayInfo
    public var availableModes: [DisplayModeOption]
    public var defaultMode: DisplayModeOption?
    public var nativeMode: DisplayModeOption?
    public var currentModeOption: DisplayModeOption?

    public init(for raw: RawDisplayInfo) {
        let availableModes = DisplayModeFilter.filterModes(for: raw)
        self.raw = raw
        self.availableModes = availableModes
        self.defaultMode = DisplayModeFilter.resolveDefaultMode(for: raw, availableModes: availableModes)
        self.nativeMode = DisplayModeFilter.resolveNativeMode(for: raw, availableModes: availableModes)
        self.currentModeOption = DisplayModeFilter.resolveCurrentModeOption(for: raw, availableModes: availableModes)
    }

    public init(
        raw: RawDisplayInfo,
        availableModes: [DisplayModeOption],
        defaultMode: DisplayModeOption?,
        nativeMode: DisplayModeOption?,
        currentModeOption: DisplayModeOption?
    ) {
        self.raw = raw
        self.availableModes = availableModes
        self.defaultMode = defaultMode
        self.nativeMode = nativeMode
        self.currentModeOption = currentModeOption
    }

    public init(display: DisplayState, raw: RawDisplayInfo) {
        self.raw = raw
        self.availableModes = display.availableModes
        self.defaultMode = display.defaultMode
        self.nativeMode = display.nativeMode
        self.currentModeOption = display.currentModeOption
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
    public var isVariableRefreshRate: Bool
    public var minRefreshRate: Double?
    public var aspectRatioKey: AspectRatioFilterKey
    public var refreshRateKey: RefreshRateFilterKey?
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
        isVariableRefreshRate: Bool = false,
        minRefreshRate: Double? = nil,
        aspectRatioKey: AspectRatioFilterKey? = nil,
        refreshRateKey: RefreshRateFilterKey? = nil,
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
        self.isVariableRefreshRate = isVariableRefreshRate
        self.minRefreshRate = minRefreshRate
        self.aspectRatioKey = aspectRatioKey ?? DisplayModeFilter.aspectRatioKey(width: width, height: height)
        self.refreshRateKey =
            refreshRateKey
            ?? (refreshRate > 0.5
                ? RefreshRateFilterKey(
                    isVariableRefreshRate: isVariableRefreshRate,
                    minRefreshRate: minRefreshRate,
                    maxRefreshRate: refreshRate
                )
                : nil)
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
    public var isVariableRefreshRate: Bool
    public var isNTSC: Bool
    public var label: String
    public var shortLabel: String

    public var id: Int32 { modeID }

    public init(
        modeID: Int32,
        refreshRate: Double,
        minRefreshRate: Double? = nil,
        isVariableRefreshRate: Bool = false,
        isNTSC: Bool = false,
        label: String,
        shortLabel: String
    ) {
        self.modeID = modeID
        self.refreshRate = refreshRate
        self.minRefreshRate = minRefreshRate
        self.isVariableRefreshRate = isVariableRefreshRate
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
    public var isVariableRefreshRate: Bool
    public var minRefreshRate: Double?

    private enum CodingKeys: String, CodingKey {
        case modeID
        case width
        case height
        case pixelWidth
        case pixelHeight
        case refreshRate
        case bitsPerSample
        case isVariableRefreshRate
        case minRefreshRate
    }

    public init(
        modeID: Int32,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        bitsPerSample: Int,
        isVariableRefreshRate: Bool = false,
        minRefreshRate: Double? = nil
    ) {
        self.modeID = modeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.bitsPerSample = bitsPerSample
        self.isVariableRefreshRate = isVariableRefreshRate
        self.minRefreshRate = minRefreshRate
    }

    public init(mode: DisplayModeOption) {
        self.init(
            modeID: mode.modeID,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate,
            bitsPerSample: mode.bitsPerSample,
            isVariableRefreshRate: mode.isVariableRefreshRate,
            minRefreshRate: mode.minRefreshRate
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modeID = try container.decode(Int32.self, forKey: .modeID)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        pixelWidth = try container.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(Int.self, forKey: .pixelHeight)
        refreshRate = try container.decode(Double.self, forKey: .refreshRate)
        bitsPerSample = try container.decode(Int.self, forKey: .bitsPerSample)
        isVariableRefreshRate = try container.decodeIfPresent(Bool.self, forKey: .isVariableRefreshRate) ?? false
        minRefreshRate = try container.decodeIfPresent(Double.self, forKey: .minRefreshRate)
    }

    public var fallbackModeOption: DisplayModeOption {
        DisplayModeFilter.fallbackModeOption(for: self)
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
