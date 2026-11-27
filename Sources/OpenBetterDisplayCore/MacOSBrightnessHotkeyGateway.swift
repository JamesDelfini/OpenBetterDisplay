import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import IOKit.hid
import IOKit.hidsystem

public struct ParsedMediaBrightnessKey: Equatable, Sendable {
    public var keyCode: Int32
    public var isKeyDown: Bool
    public var isKeyUp: Bool
    public var event: BrightnessKeyEvent

    public init(
        keyCode: Int32,
        isKeyDown: Bool,
        isKeyUp: Bool,
        event: BrightnessKeyEvent
    ) {
        self.keyCode = keyCode
        self.isKeyDown = isKeyDown
        self.isKeyUp = isKeyUp
        self.event = event
    }
}

public enum BrightnessKeyEventParser {
    private static let keyDownState = 0x0A
    private static let keyUpState = 0x0B
    private static let repeatFlagMask = 0x0001

    public static func parseMediaKeyData(
        data1: Int,
        isFineModifierActive: Bool,
        pointerLocation: CGPoint?
    ) -> ParsedMediaBrightnessKey? {
        let keyCode = Int32((data1 & 0xFFFF_0000) >> 16)
        let direction: BrightnessKeyDirection
        switch keyCode {
        case NX_KEYTYPE_BRIGHTNESS_UP:
            direction = .increase
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            direction = .decrease
        default:
            return nil
        }

        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == keyDownState
        let isKeyUp = keyState == keyUpState
        guard isKeyDown || isKeyUp else {
            return nil
        }

        let isRepeat = (keyFlags & repeatFlagMask) != 0
        let event = BrightnessKeyEvent(
            direction: direction,
            source: .mediaBrightness,
            isFine: isFineModifierActive,
            isRepeat: isRepeat,
            pointerLocation: pointerLocation
        )
        return ParsedMediaBrightnessKey(
            keyCode: keyCode,
            isKeyDown: isKeyDown,
            isKeyUp: isKeyUp,
            event: event
        )
    }

    public static func convertAppKitPointerToCoreGraphics(
        _ mouseLocation: CGPoint,
        mainDisplayHeight: CGFloat
    ) -> CGPoint? {
        guard mainDisplayHeight > 0 else {
            return nil
        }
        return CGPoint(x: mouseLocation.x, y: mainDisplayHeight - mouseLocation.y)
    }

    public static func resolveFunctionKeyMode(
        hidFKeyMode: Int?,
        cfPreferenceFnState: Bool?
    ) -> FunctionKeyMode {
        if let hidFKeyMode {
            switch hidFKeyMode {
            case 0:
                return .mediaKeys
            case 1:
                return .standardFunctionKeys
            default:
                break
            }
        }
        if let cfPreferenceFnState {
            return cfPreferenceFnState ? .standardFunctionKeys : .mediaKeys
        }
        return .unknown
    }
}

@MainActor
public final class MacOSBrightnessHotkeyGateway: BrightnessHotkeyGateway {
    private typealias IOHIDEventSystemClientCreateFn =
        @convention(c) (CFAllocator?) -> Unmanaged<IOHIDEventSystemClient>?

    private enum HotKeyIdentifier: UInt32, CaseIterable {
        case decrease = 1
        case increase = 2
        case fineDecrease = 3
        case fineIncrease = 4

        var keyCode: UInt32 {
            switch self {
            case .decrease, .fineDecrease:
                return UInt32(kVK_F1)
            case .increase, .fineIncrease:
                return UInt32(kVK_F2)
            }
        }

        var modifiers: UInt32 {
            switch self {
            case .decrease, .increase:
                return 0
            case .fineDecrease, .fineIncrease:
                return UInt32(optionKey | shiftKey)
            }
        }

        var direction: BrightnessKeyDirection {
            switch self {
            case .decrease, .fineDecrease:
                return .decrease
            case .increase, .fineIncrease:
                return .increase
            }
        }

        var isFine: Bool {
            switch self {
            case .decrease, .increase:
                return false
            case .fineDecrease, .fineIncrease:
                return true
            }
        }
    }

    private static let hotKeySignature: OSType = 0x4F42_4448
    private static let fnStateNotificationName = Notification.Name("com.apple.keyboard.fnstatedidchange")
    private static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    public var onBrightnessKeyEvent: (@MainActor (BrightnessKeyEvent) -> Bool)?
    public var onCheckerStatusDidChange: (@MainActor () -> Void)?

    private let ioHIDEventSystemClientCreate: IOHIDEventSystemClientCreateFn?
    private let hudPresenter: BrightnessHUDPresenting?
    private var currentPreferences = HotkeyPreferences()
    private nonisolated(unsafe) var mediaEventTap: CFMachPort?
    private nonisolated(unsafe) var mediaRunLoopSource: CFRunLoopSource?
    private var consumedMediaKeyCodes: Set<Int32> = []
    private nonisolated(unsafe) var carbonEventHandler: EventHandlerRef?
    private nonisolated(unsafe) var registeredHotKeyRefs: [EventHotKeyRef] = []
    private nonisolated(unsafe) var repeatDelayTimer: Timer?
    private nonisolated(unsafe) var repeatIntervalTimer: Timer?
    private var activeRepeatHotKey: HotKeyIdentifier?
    private nonisolated(unsafe) var fnStateObserver: NSObjectProtocol?
    private nonisolated(unsafe) var appDidBecomeActiveObserver: NSObjectProtocol?

    public init(hudPresenter: BrightnessHUDPresenting? = nil) {
        let ioKit = DynamicLibrary(path: "/System/Library/Frameworks/IOKit.framework/IOKit")
        self.ioHIDEventSystemClientCreate = ioKit.symbol("IOHIDEventSystemClientCreate")
        self.hudPresenter = hudPresenter
        startStatusObservers()
    }

    deinit {
        stopSystemCaptureAndObservers()
    }

    public func applyPreferences(_ preferences: HotkeyPreferences) {
        currentPreferences = preferences
        syncMediaEventTap()
        syncLiteralF1F2HotKeys()
    }

    public func readCheckerStatus() -> KeyboardCheckerStatus {
        let isTrusted = AXIsProcessTrusted()
        syncMediaEventTap(isAccessibilityTrusted: isTrusted)

        return KeyboardCheckerStatus(
            functionKeyMode: readFunctionKeyMode(),
            isAccessibilityTrusted: isTrusted,
            isMediaKeyCaptureActive: mediaEventTap != nil,
            isLiteralF1F2Active: !registeredHotKeyRefs.isEmpty
        )
    }

    public func currentPointerLocation() -> CGPoint? {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return BrightnessKeyEventParser.convertAppKitPointerToCoreGraphics(
            NSEvent.mouseLocation,
            mainDisplayHeight: mainHeight
        )
    }

    public func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted, let url = Self.accessibilitySettingsURL {
            NSWorkspace.shared.open(url)
        }
        syncMediaEventTap(isAccessibilityTrusted: isTrusted)
    }

    public func openKeyboardSettings() {
        guard let url = Self.keyboardSettingsURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func showBrightnessHUD(_ updates: [BrightnessHUDUpdate]) {
        guard !updates.isEmpty else { return }
        hudPresenter?.showBrightnessHUD(updates)
    }

    public func stop() {
        stopSystemCaptureAndObservers()
        hudPresenter?.dismissAllBrightnessHUDs()
    }

    nonisolated private func stopSystemCaptureAndObservers() {
        stopRepeatTimers()
        unregisterLiteralHotKeys()
        stopMediaEventTap()

        if let fnStateObserver {
            DistributedNotificationCenter.default().removeObserver(fnStateObserver)
            self.fnStateObserver = nil
        }
        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
            self.appDidBecomeActiveObserver = nil
        }
    }

    // MARK: - Function Key Mode Checker & Observers

    private func startStatusObservers() {
        fnStateObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.fnStateNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onCheckerStatusDidChange?()
            }
        }

        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onCheckerStatusDidChange?()
            }
        }
    }

    private func readFunctionKeyMode() -> FunctionKeyMode {
        var hidMode: Int?
        if let ioHIDEventSystemClientCreate,
            let client = ioHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue(),
            let value = IOHIDEventSystemClientCopyProperty(client, "HIDFKeyMode" as CFString) as? NSNumber
        {
            hidMode = value.intValue
        }

        let cfPrefFnState =
            CFPreferencesCopyAppValue("com.apple.keyboard.fnState" as CFString, kCFPreferencesAnyApplication) as? Bool
        return BrightnessKeyEventParser.resolveFunctionKeyMode(
            hidFKeyMode: hidMode,
            cfPreferenceFnState: cfPrefFnState
        )
    }

    // MARK: - Media Key CGEventTap

    private func syncMediaEventTap(isAccessibilityTrusted: Bool? = nil) {
        let trusted = isAccessibilityTrusted ?? AXIsProcessTrusted()
        // Never invoke CGEventTapCreate unless Accessibility is already trusted, so launch never triggers TCC prompts.
        guard currentPreferences.isMediaKeysEnabled, trusted else {
            stopMediaEventTap()
            return
        }

        if let existingTap = mediaEventTap {
            CGEvent.tapEnable(tap: existingTap, enable: true)
            return
        }

        let eventMask = CGEventMask(1 << NX_SYSDEFINED)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: Self.mediaEventTapCallback,
                userInfo: userInfo
            )
        else {
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        mediaEventTap = tap
        mediaRunLoopSource = source
    }

    nonisolated private func stopMediaEventTap() {
        if let source = mediaRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            mediaRunLoopSource = nil
        }
        if let tap = mediaEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            mediaEventTap = nil
        }
    }

    nonisolated private static let mediaEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let gateway = Unmanaged<MacOSBrightnessHotkeyGateway>.fromOpaque(userInfo).takeUnretainedValue()
        return MainActor.assumeIsolated {
            gateway.handleMediaTapEvent(type: type, event: event)
        }
    }

    private func handleMediaTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let mediaEventTap {
                CGEvent.tapEnable(tap: mediaEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
            nsEvent.type == .systemDefined,
            nsEvent.subtype.rawValue == Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS)
        else {
            return Unmanaged.passUnretained(event)
        }

        let isFine = nsEvent.modifierFlags.intersection([.option, .shift]) == [.option, .shift]
        guard
            let parsed = BrightnessKeyEventParser.parseMediaKeyData(
                data1: nsEvent.data1,
                isFineModifierActive: isFine,
                pointerLocation: currentPointerLocation()
            )
        else {
            return Unmanaged.passUnretained(event)
        }

        if parsed.isKeyDown {
            let shouldConsume = onBrightnessKeyEvent?(parsed.event) ?? false
            if shouldConsume {
                consumedMediaKeyCodes.insert(parsed.keyCode)
                return nil
            }
            consumedMediaKeyCodes.remove(parsed.keyCode)
            return Unmanaged.passUnretained(event)
        }

        if parsed.isKeyUp, consumedMediaKeyCodes.remove(parsed.keyCode) != nil {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Opt-in Carbon Literal F1 / F2

    private func syncLiteralF1F2HotKeys() {
        guard currentPreferences.isLiteralF1F2Enabled else {
            stopRepeatTimers()
            activeRepeatHotKey = nil
            unregisterLiteralHotKeys()
            return
        }

        guard registeredHotKeyRefs.isEmpty else {
            return
        }

        let eventSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        var handlerRef: EventHandlerRef?
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonHotKeyHandler,
            eventSpecs.count,
            eventSpecs,
            userInfo,
            &handlerRef
        )
        guard handlerStatus == noErr, let handlerRef else {
            return
        }
        carbonEventHandler = handlerRef

        for identifier in HotKeyIdentifier.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: identifier.rawValue)
            let status = RegisterEventHotKey(
                identifier.keyCode,
                identifier.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let hotKeyRef {
                registeredHotKeyRefs.append(hotKeyRef)
            }
        }

        if registeredHotKeyRefs.isEmpty {
            unregisterLiteralHotKeys()
        }
    }

    nonisolated private func unregisterLiteralHotKeys() {
        for hotKeyRef in registeredHotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        registeredHotKeyRefs.removeAll()

        if let carbonEventHandler {
            RemoveEventHandler(carbonEventHandler)
            self.carbonEventHandler = nil
        }
    }

    nonisolated private static let carbonHotKeyHandler: EventHandlerUPP = { _, event, userInfo in
        guard let event, let userInfo else {
            return OSStatus(eventNotHandledErr)
        }
        let gateway = Unmanaged<MacOSBrightnessHotkeyGateway>.fromOpaque(userInfo).takeUnretainedValue()
        return MainActor.assumeIsolated {
            gateway.handleCarbonHotKeyEvent(event)
        }
    }

    private func handleCarbonHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let paramErr = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard paramErr == noErr,
            hotKeyID.signature == Self.hotKeySignature,
            let identifier = HotKeyIdentifier(rawValue: hotKeyID.id)
        else {
            return OSStatus(eventNotHandledErr)
        }

        let eventKind = GetEventKind(event)
        if eventKind == UInt32(kEventHotKeyPressed) {
            stopRepeatTimers()
            activeRepeatHotKey = identifier
            dispatchCarbonStep(identifier, isRepeat: false)
            scheduleCarbonHoldRepeat(for: identifier)
            return noErr
        }
        if eventKind == UInt32(kEventHotKeyReleased) {
            if activeRepeatHotKey == identifier {
                stopRepeatTimers()
                activeRepeatHotKey = nil
            }
            return noErr
        }

        return OSStatus(eventNotHandledErr)
    }

    private func dispatchCarbonStep(_ identifier: HotKeyIdentifier, isRepeat: Bool) {
        let keyEvent = BrightnessKeyEvent(
            direction: identifier.direction,
            source: .literalFunctionKey,
            isFine: identifier.isFine,
            isRepeat: isRepeat,
            pointerLocation: currentPointerLocation()
        )
        _ = onBrightnessKeyEvent?(keyEvent)
    }

    private func scheduleCarbonHoldRepeat(for identifier: HotKeyIdentifier) {
        let initialDelay = NSEvent.keyRepeatDelay > 0 ? NSEvent.keyRepeatDelay : 0.4
        let repeatInterval = NSEvent.keyRepeatInterval > 0 ? NSEvent.keyRepeatInterval : 0.08

        let delayTimer = Timer(timeInterval: initialDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.activeRepeatHotKey == identifier else {
                    return
                }
                self.dispatchCarbonStep(identifier, isRepeat: true)

                let intervalTimer = Timer(timeInterval: repeatInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.activeRepeatHotKey == identifier else {
                            return
                        }
                        self.dispatchCarbonStep(identifier, isRepeat: true)
                    }
                }
                RunLoop.main.add(intervalTimer, forMode: .common)
                self.repeatIntervalTimer = intervalTimer
            }
        }
        RunLoop.main.add(delayTimer, forMode: .common)
        repeatDelayTimer = delayTimer
    }

    nonisolated private func stopRepeatTimers() {
        repeatDelayTimer?.invalidate()
        repeatDelayTimer = nil
        repeatIntervalTimer?.invalidate()
        repeatIntervalTimer = nil
    }
}
