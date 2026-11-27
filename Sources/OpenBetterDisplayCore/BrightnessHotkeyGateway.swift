import CoreGraphics
import Foundation

public enum HotkeyTargetMode: String, Codable, CaseIterable, Equatable, Sendable {
    case followMouseCursor
    case allEnabledDisplays
    case mainDisplay

    public var label: String {
        switch self {
        case .followMouseCursor:
            return "Follow Mouse Cursor"
        case .allEnabledDisplays:
            return "All Enabled Displays"
        case .mainDisplay:
            return "Main Display"
        }
    }

    public var compactLabel: String {
        switch self {
        case .followMouseCursor:
            return "Cursor"
        case .allEnabledDisplays:
            return "All"
        case .mainDisplay:
            return "Main"
        }
    }
}

public struct HotkeyPreferences: Codable, Equatable, Sendable {
    public var targetMode: HotkeyTargetMode
    public var isMediaKeysEnabled: Bool
    public var isLiteralF1F2Enabled: Bool

    public init(
        targetMode: HotkeyTargetMode = .followMouseCursor,
        isMediaKeysEnabled: Bool = true,
        isLiteralF1F2Enabled: Bool = false
    ) {
        self.targetMode = targetMode
        self.isMediaKeysEnabled = isMediaKeysEnabled
        self.isLiteralF1F2Enabled = isLiteralF1F2Enabled
    }
}

public enum BrightnessKeyDirection: Equatable, Sendable {
    case decrease
    case increase
}

public enum BrightnessKeySource: Equatable, Sendable {
    case mediaBrightness
    case literalFunctionKey
}

public struct BrightnessKeyEvent: Equatable, Sendable {
    public var direction: BrightnessKeyDirection
    public var source: BrightnessKeySource
    public var isFine: Bool
    public var isRepeat: Bool
    public var pointerLocation: CGPoint?

    public init(
        direction: BrightnessKeyDirection,
        source: BrightnessKeySource,
        isFine: Bool = false,
        isRepeat: Bool = false,
        pointerLocation: CGPoint? = nil
    ) {
        self.direction = direction
        self.source = source
        self.isFine = isFine
        self.isRepeat = isRepeat
        self.pointerLocation = pointerLocation
    }
}

public enum FunctionKeyMode: Equatable, Sendable {
    case mediaKeys
    case standardFunctionKeys
    case unknown
}

public struct KeyboardCheckerStatus: Equatable, Sendable {
    public var functionKeyMode: FunctionKeyMode
    public var isAccessibilityTrusted: Bool
    public var isMediaKeyCaptureActive: Bool
    public var isLiteralF1F2Active: Bool

    public init(
        functionKeyMode: FunctionKeyMode = .unknown,
        isAccessibilityTrusted: Bool = false,
        isMediaKeyCaptureActive: Bool = false,
        isLiteralF1F2Active: Bool = false
    ) {
        self.functionKeyMode = functionKeyMode
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.isMediaKeyCaptureActive = isMediaKeyCaptureActive
        self.isLiteralF1F2Active = isLiteralF1F2Active
    }
}

public struct BrightnessHUDUpdate: Equatable, Sendable {
    public var displayID: UInt32
    public var displayName: String
    public var symbolName: String
    public var brightness: Double
    public var brightnessPercentage: Int
    public var backend: BrightnessBackendUsed

    public init(
        displayID: UInt32,
        displayName: String,
        symbolName: String,
        brightness: Double,
        brightnessPercentage: Int,
        backend: BrightnessBackendUsed
    ) {
        self.displayID = displayID
        self.displayName = displayName
        self.symbolName = symbolName
        self.brightness = brightness
        self.brightnessPercentage = brightnessPercentage
        self.backend = backend
    }
}

public protocol HotkeyPreferencesPersistence: Sendable {
    func loadPreferences() -> HotkeyPreferences?
    func savePreferences(_ preferences: HotkeyPreferences)
}

public final class UserDefaultsHotkeyPreferencesStore: HotkeyPreferencesPersistence, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "OpenBetterDisplay.hotkeyPreferences"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    public func loadPreferences() -> HotkeyPreferences? {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(HotkeyPreferences.self, from: data)
    }

    public func savePreferences(_ preferences: HotkeyPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }
}

@MainActor
public protocol BrightnessHotkeyGateway: AnyObject {
    var onBrightnessKeyEvent: (@MainActor (BrightnessKeyEvent) -> Bool)? { get set }
    var onCheckerStatusDidChange: (@MainActor () -> Void)? { get set }

    func applyPreferences(_ preferences: HotkeyPreferences)
    func readCheckerStatus() -> KeyboardCheckerStatus
    func currentPointerLocation() -> CGPoint?
    func requestAccessibilityPermission()
    func openKeyboardSettings()
    func stop()
}
