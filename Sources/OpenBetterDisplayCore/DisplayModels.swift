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

    public init(
        modeID: Int32,
        width: Int,
        height: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        refreshRate: Double = 60.0,
        isUsableForDesktopGUI: Bool = true
    ) {
        self.modeID = modeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth ?? width
        self.pixelHeight = pixelHeight ?? height
        self.refreshRate = refreshRate
        self.isUsableForDesktopGUI = isUsableForDesktopGUI
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
        modes: [RawDisplayMode] = []
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
    }
}

public struct DisplayModeOption: Equatable, Identifiable, Sendable {
    public var modeID: Int32
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double
    public var isHiDPI: Bool
    public var scalePercentage: Int
    public var label: String

    public var id: Int32 { modeID }

    public init(
        modeID: Int32,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        isHiDPI: Bool,
        scalePercentage: Int,
        label: String
    ) {
        self.modeID = modeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.isHiDPI = isHiDPI
        self.scalePercentage = scalePercentage
        self.label = label
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
    public var symbolName: String
    public var brightness: Double
    public var brightnessBackend: BrightnessBackendUsed
    public var availableModes: [DisplayModeOption]
    public var currentModeID: Int32
    public var previewModeID: Int32?

    public var id: UInt32 { displayID }

    public var canSetAsMain: Bool {
        isEnabled && !isMain
    }

    public var brightnessPercentage: Int {
        Int((brightness * 100.0).rounded())
    }

    public init(
        displayID: UInt32,
        name: String,
        isBuiltIn: Bool = false,
        isMain: Bool = false,
        isEnabled: Bool = true,
        canToggleOff: Bool = false,
        symbolName: String = "",
        brightness: Double = 1.0,
        brightnessBackend: BrightnessBackendUsed = .hardwareDDC,
        availableModes: [DisplayModeOption] = [],
        currentModeID: Int32 = 0,
        previewModeID: Int32? = nil
    ) {
        self.displayID = displayID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
        self.isEnabled = isEnabled
        self.canToggleOff = canToggleOff
        self.symbolName = symbolName
        self.brightness = brightness
        self.brightnessBackend = brightnessBackend
        self.availableModes = availableModes
        self.currentModeID = currentModeID
        self.previewModeID = previewModeID
    }
}
